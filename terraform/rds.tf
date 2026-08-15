resource "aws_db_subnet_group" "blog" {
  name       = "blog-rds"
  subnet_ids = data.aws_subnets.default.ids

  tags = { Name = "blog-rds" }
}

resource "aws_db_instance" "blog" {
  identifier     = "personal-blog-db"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  db_name  = "personal_blog"
  username = "blog"
  password = var.db_master_password

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.blog.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # The API verifies TLS against the regional CA bundle baked into its image,
  # so the CA is pinned rather than left to whatever the account default is.
  ca_cert_identifier = "rds-ca-rsa2048-g1"

  backup_retention_period = 7
  deletion_protection     = true
  skip_final_snapshot     = true

  lifecycle {
    # AWS applies minor engine upgrades automatically; don't fight the drift.
    ignore_changes = [engine_version]
  }
}
