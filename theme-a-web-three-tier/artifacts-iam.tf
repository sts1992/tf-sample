# Only these reviewed files may be deployed. A directory-wide archive can silently
# include local credentials (for example .npmrc, private keys or nested .env files).
locals {
  artifact_files = {
    web = ["app.jsx", "index.html", "package.json", "package-lock.json"]
    app = ["handler.mjs", "server.mjs", "package.json", "package-lock.json"]
  }
}
# Source archives are uploaded by Terraform apply, never by the EC2 bootstrap.
data "archive_file" "demo" {
  for_each    = local.tiers
  type        = "zip"
  output_path = "${path.module}/${each.key}-artifact.zip"
  dynamic "source" {
    for_each = local.artifact_files[each.key]
    content {
      filename = source.value
      content  = file("${path.module}/demo/${each.key}/${source.value}")
    }
  }
}
resource "aws_s3_bucket" "artifacts" {
  bucket_prefix = "${var.name}-artifacts-"
  force_destroy = true # Contains replaceable demo source only, never DB data.
}
resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*"
      Resource  = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}
resource "aws_s3_object" "demo" {
  for_each     = local.tiers
  bucket       = aws_s3_bucket.artifacts.id
  key          = "${each.key}/${data.archive_file.demo[each.key].output_sha256}.zip"
  source       = data.archive_file.demo[each.key].output_path
  source_hash  = data.archive_file.demo[each.key].output_sha256
  content_type = "application/zip"
  depends_on   = [aws_s3_bucket_server_side_encryption_configuration.artifacts, aws_s3_bucket_public_access_block.artifacts]
}
resource "aws_iam_role" "ec2" {
  for_each    = local.tiers
  name_prefix = "${var.name}-${each.key}-"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  for_each   = local.tiers
  role       = aws_iam_role.ec2[each.key].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy" "artifact" {
  for_each = local.tiers
  name     = "ReadOwnDemoArtifact"
  role     = aws_iam_role.ec2[each.key].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["s3:GetObject"], Resource = [aws_s3_object.demo[each.key].arn] }]
  })
}
resource "aws_iam_role_policy" "database_secret" {
  name = "ReadOnlyThisDatabaseSecret"
  role = aws_iam_role.ec2["app"].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = [aws_rds_cluster.this.master_user_secret[0].secret_arn] }]
  })
}
resource "aws_iam_instance_profile" "ec2" {
  for_each    = local.tiers
  name_prefix = "${var.name}-${each.key}-"
  role        = aws_iam_role.ec2[each.key].name
}
