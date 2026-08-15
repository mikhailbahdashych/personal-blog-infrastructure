output "public_ip" {
  description = "Elastic IP — the value the Cloudflare A records (apex, api., admin.) point at"
  value       = aws_eip.blog.public_ip
}

output "instance_id" {
  value = aws_instance.blog.id
}

output "ec2_security_group_id" {
  description = "Goes into the EC2_SG_ID repo secret (deploys open/close port 22 on it)"
  value       = aws_security_group.ec2.id
}

output "rds_endpoint" {
  value = aws_db_instance.blog.address
}

output "database_url" {
  description = "Ready-made DATABASE_URL for the host's .env.prod"
  value       = "postgres://${aws_db_instance.blog.username}:${var.db_master_password}@${aws_db_instance.blog.address}:5432/${aws_db_instance.blog.db_name}"
  sensitive   = true
}

output "ci_access_key_id" {
  description = "Goes into the AWS_ACCESS_KEY_ID repo secret"
  value       = aws_iam_access_key.ci_sg.id
}

output "ci_secret_access_key" {
  description = "Goes into the AWS_SECRET_ACCESS_KEY repo secret"
  value       = aws_iam_access_key.ci_sg.secret
  sensitive   = true
}

output "s3_access_key_id" {
  description = "Goes into S3_ACCESS_KEY_ID in the host's .env.prod"
  value       = aws_iam_access_key.s3.id
}

output "s3_secret_access_key" {
  description = "Goes into S3_SECRET_ACCESS_KEY in the host's .env.prod"
  value       = aws_iam_access_key.s3.secret
  sensitive   = true
}
