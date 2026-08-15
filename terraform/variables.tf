variable "aws_region" {
  description = "AWS region everything lives in"
  type        = string
  default     = "eu-central-1"
}

variable "instance_type" {
  description = "EC2 instance type for the single application host"
  type        = string
  default     = "t3a.small"
}

variable "ssh_public_key" {
  description = "Public half of the deploy key (the private half stays with the operator and in the repos' EC2_SSH_KEY secret)"
  type        = string
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version. Minor upgrades are applied automatically by AWS afterwards, so this only matters at creation time."
  type        = string
  default     = "16.11"
}

variable "db_master_password" {
  description = "Master password for the RDS instance (user 'blog'). Generate with: openssl rand -hex 24"
  type        = string
  sensitive   = true
}

variable "assets_bucket" {
  description = <<-EOT
    Name of the pre-existing S3 bucket holding uploaded assets. The bucket is
    shared with the dev environment (dev/ and prod/ key prefixes) and holds
    data, so Terraform references it but does not manage or ever destroy it.
    See the README for the bucket policy / CORS it is expected to carry.
  EOT
  type        = string
  default     = "bahdashych-on-security"
}

variable "infra_repo_url" {
  description = "Public git URL of this repository; cloud-init clones it to /opt/blog on the host"
  type        = string
  default     = "https://github.com/mikhailbahdashych/personal-blog-infrastructure.git"
}
