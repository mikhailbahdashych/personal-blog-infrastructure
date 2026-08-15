# Two single-purpose IAM users, each holding exactly one capability:
#
#   blog-s3     — object CRUD in the shared assets bucket; its keys live in the
#                 host's .env.prod and nowhere else.
#   blog-ci-sg  — open/close port 22 on the EC2 security group; its keys live
#                 in the GitHub Actions secrets of the app repos, letting every
#                 deploy SSH in from the runner's IP without the port sitting
#                 open in between.

resource "aws_iam_user" "s3" {
  name = "blog-s3"
}

resource "aws_iam_user_policy" "s3_objects" {
  name = "blog-s3-objects"
  user = aws_iam_user.s3.name

  # Bucket-wide (not prefix-scoped) on purpose: dev and prod share the bucket
  # under dev/ and prod/ prefixes, and local dev uses these same credentials.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::${var.assets_bucket}/*"
      }
    ]
  })
}

resource "aws_iam_access_key" "s3" {
  user = aws_iam_user.s3.name
}

resource "aws_iam_user" "ci_sg" {
  name = "blog-ci-sg"
}

resource "aws_iam_user_policy" "ci_ssh_gate" {
  name = "blog-ci-ssh-gate"
  user = aws_iam_user.ci_sg.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"]
        Resource = aws_security_group.ec2.arn
      }
    ]
  })
}

resource "aws_iam_access_key" "ci_sg" {
  user = aws_iam_user.ci_sg.name
}
