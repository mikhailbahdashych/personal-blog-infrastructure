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

resource "aws_vpc_security_group_ingress_rule" "http_v4" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTP (ACME challenges + redirect to HTTPS)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "http_v6" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTP (ACME challenges + redirect to HTTPS)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv6         = "::/0"
}

resource "aws_vpc_security_group_ingress_rule" "https_v4" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTPS"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "https_v6" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTPS"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = "::/0"
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
