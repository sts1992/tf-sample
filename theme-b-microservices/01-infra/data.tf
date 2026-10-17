resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-data"
  subnet_ids = [for s in aws_subnet.data : s.id]
}
# Upstream Catalog 1.6.3 does not set MySQL TLS in its DSN. Educational example only.
resource "aws_db_parameter_group" "mysql" {
  name_prefix = "${var.name}-mysql-"
  family      = "mysql8.0"
  parameter {
    name  = "require_secure_transport"
    value = "OFF"
  }
  lifecycle { create_before_destroy = true }
}
resource "aws_db_parameter_group" "postgres" {
  name_prefix = "${var.name}-postgres-"
  family      = "postgres16"
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
  lifecycle { create_before_destroy = true }
}
resource "aws_db_instance" "catalog" {
  identifier                  = "${var.name}-catalog"
  engine                      = "mysql"
  engine_version              = var.mysql_engine_version
  instance_class              = var.db_instance_class
  allocated_storage           = 20
  max_allocated_storage       = 100
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = "catalog"
  username                    = "catalogadmin"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.this.name
  vpc_security_group_ids      = [aws_security_group.data["mysql"].id]
  parameter_group_name        = aws_db_parameter_group.mysql.name
  publicly_accessible         = false
  multi_az                    = var.db_multi_az
  backup_retention_period     = 7
  auto_minor_version_upgrade  = true
  deletion_protection         = var.deletion_protection
  skip_final_snapshot         = var.skip_final_snapshot
  final_snapshot_identifier   = "${var.name}-catalog-${var.final_snapshot_suffix}"
  copy_tags_to_snapshot       = true
}
resource "aws_db_instance" "orders" {
  identifier                  = "${var.name}-orders"
  engine                      = "postgres"
  engine_version              = var.postgres_engine_version
  instance_class              = var.db_instance_class
  allocated_storage           = 20
  max_allocated_storage       = 100
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = "orders"
  username                    = "ordersadmin"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.this.name
  vpc_security_group_ids      = [aws_security_group.data["postgres"].id]
  parameter_group_name        = aws_db_parameter_group.postgres.name
  publicly_accessible         = false
  multi_az                    = var.db_multi_az
  backup_retention_period     = 7
  auto_minor_version_upgrade  = true
  deletion_protection         = var.deletion_protection
  skip_final_snapshot         = var.skip_final_snapshot
  final_snapshot_identifier   = "${var.name}-orders-${var.final_snapshot_suffix}"
  copy_tags_to_snapshot       = true
}
resource "aws_dynamodb_table" "carts" {
  name         = "${var.name}-carts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
  attribute {
    name = "id"
    type = "S"
  }
  attribute {
    name = "customerId"
    type = "S"
  }
  global_secondary_index {
    name            = "idx_global_customerId"
    hash_key        = "customerId"
    projection_type = "ALL"
  }
  point_in_time_recovery { enabled = true }
  server_side_encryption { enabled = true }
  deletion_protection_enabled = var.deletion_protection
}
resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name}-redis"
  subnet_ids = [for s in aws_subnet.data : s.id]
}
resource "aws_elasticache_replication_group" "checkout" {
  replication_group_id       = "${var.name}-checkout"
  description                = "Checkout TLS Redis, single primary plus replica"
  engine                     = "redis"
  engine_version             = "7.1"
  parameter_group_name       = "default.redis7"
  node_type                  = var.redis_node_type
  num_cache_clusters         = 2
  automatic_failover_enabled = true
  multi_az_enabled           = true
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.this.name
  security_group_ids         = [aws_security_group.data["redis"].id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"
  snapshot_retention_limit   = 1
  # Demo: no AUTH token. Network is restricted to the worker-node SG.
  # Add Redis ACL/user-group authentication for production and rotate outside Terraform state.
}
resource "aws_sqs_queue" "orders" {
  name                       = "${var.name}-orders"
  sqs_managed_sse_enabled    = true
  message_retention_seconds  = 345600
  visibility_timeout_seconds = 30
}
resource "aws_sqs_queue_policy" "tls_only" {
  queue_url = aws_sqs_queue.orders.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Sid       = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "sqs:*", Resource = aws_sqs_queue.orders.arn,
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }] })
}
