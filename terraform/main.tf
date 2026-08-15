# The stack deliberately runs in the account's default VPC: a single-host blog
# does not need private subnets or NAT, and RDS stays unreachable from the
# internet through its security group + publicly_accessible = false.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Canonical's rolling pointer to the latest Ubuntu 24.04 LTS AMD64 server AMI.
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}
