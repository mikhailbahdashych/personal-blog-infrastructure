resource "aws_key_pair" "deployer" {
  key_name   = "blog-deployer"
  public_key = var.ssh_public_key
}

resource "aws_instance" "blog" {
  ami           = nonsensitive(data.aws_ssm_parameter.ubuntu_ami.value)
  instance_type = var.instance_type
  key_name      = aws_key_pair.deployer.key_name

  # sort() pins the choice: aws_subnets returns ids in no particular order, and
  # a different pick on a later plan would force an instance replacement.
  subnet_id              = sort(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids = [aws_security_group.ec2.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/cloud-init.sh.tftpl", {
    repo_url = var.infra_repo_url
  })

  lifecycle {
    # Canonical's SSM pointer moves with every AMI release; following it would
    # replace the server. New AMIs are picked up only on deliberate rebuilds.
    ignore_changes = [ami]
  }

  tags = { Name = "blog" }
}

# The public IP of the whole deployment. DNS (Cloudflare) points the apex,
# api. and admin. records here, so this allocation must survive instance
# rebuilds — it is never destroyed with the rest of the stack. On an existing
# account, bring the allocation in instead of creating a fresh one:
#
#   terraform import aws_eip.blog eipalloc-xxxxxxxxxxxxxxxxx
resource "aws_eip" "blog" {
  domain = "vpc"
  tags   = { Name = "blog" }
}

resource "aws_eip_association" "blog" {
  allocation_id = aws_eip.blog.id
  instance_id   = aws_instance.blog.id
}
