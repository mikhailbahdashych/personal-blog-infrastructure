# Security-group rules live in standalone rule resources, not inline blocks.
# That keeps Terraform non-authoritative over rules it does not declare — the
# deploy pipelines add and revoke a port-22 rule for the runner's IP on every
# deploy, and an inline-rule SG would revert or trip over that on each apply.

resource "aws_security_group" "ec2" {
  name        = "blog-ec2-sg"
  description = "Blog EC2: web from anywhere, SSH ephemeral via CI"
  vpc_id      = data.aws_vpc.default.id

  tags = { Name = "blog-ec2-sg" }
}

# Web ingress. With restrict_web_to_cloudflare (the default), 80/443 admit
# only Cloudflare's published edge ranges — fetched live at plan time, so an
# apply after Cloudflare changes them (rare) updates the rules. nginx trusts
# CF-Connecting-IP from exactly the same ranges (deploy/nginx/
# cloudflare-real-ip.conf), which is what keeps the admin allowlist and
# per-client rate limiting working behind the proxy.
data "http" "cloudflare_ips_v4" {
  url = "https://www.cloudflare.com/ips-v4"
}

data "http" "cloudflare_ips_v6" {
  url = "https://www.cloudflare.com/ips-v6"
}

locals {
  web_ports = [80, 443]

  web_cidrs_v4 = var.restrict_web_to_cloudflare ? [
    for l in split("\n", trimspace(data.http.cloudflare_ips_v4.response_body)) : trimspace(l) if trimspace(l) != ""
  ] : ["0.0.0.0/0"]

  web_cidrs_v6 = var.restrict_web_to_cloudflare ? [
    for l in split("\n", trimspace(data.http.cloudflare_ips_v6.response_body)) : trimspace(l) if trimspace(l) != ""
  ] : ["::/0"]
}

resource "aws_vpc_security_group_ingress_rule" "web_v4" {
  for_each = {
    for pair in setproduct(local.web_ports, local.web_cidrs_v4) : "${pair[0]}-${pair[1]}" => pair
  }

  security_group_id = aws_security_group.ec2.id
  description       = var.restrict_web_to_cloudflare ? "Web via Cloudflare only" : "Web open to the world"
  ip_protocol       = "tcp"
  from_port         = each.value[0]
  to_port           = each.value[0]
  cidr_ipv4         = each.value[1]
}

resource "aws_vpc_security_group_ingress_rule" "web_v6" {
  for_each = {
    for pair in setproduct(local.web_ports, local.web_cidrs_v6) : "${pair[0]}-${pair[1]}" => pair
  }

  security_group_id = aws_security_group.ec2.id
  description       = var.restrict_web_to_cloudflare ? "Web via Cloudflare only" : "Web open to the world"
  ip_protocol       = "tcp"
  from_port         = each.value[0]
  to_port           = each.value[0]
  cidr_ipv6         = each.value[1]
}

resource "aws_vpc_security_group_egress_rule" "all_v4" {
  security_group_id = aws_security_group.ec2.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "all_v6" {
  security_group_id = aws_security_group.ec2.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}

# RDS accepts Postgres connections only from the EC2 security group — there is
# no path to the database from the internet.
resource "aws_security_group" "rds" {
  name        = "blog-rds-sg"
  description = "Blog RDS: postgres from blog-ec2-sg only"
  vpc_id      = data.aws_vpc.default.id

  tags = { Name = "blog-rds-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_ec2" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL from the blog host"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.ec2.id
}
