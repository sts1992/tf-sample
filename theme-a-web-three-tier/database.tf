resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = [for s in aws_subnet.db : s.id]
}
resource "aws_rds_cluster_parameter_group" "this" {
  name_prefix = "${var.name}-"
  family      = "aurora-mysql8.0"
  description = "Require TLS for Aurora MySQL connections"
  parameter {
    name  = "require_secure_transport"
    value = "ON"
  }
  lifecycle { create_before_destroy = true }
}
resource "aws_rds_cluster" "this" {
  cluster_identifier              = var.name
  engine                          = "aurora-mysql"
  engine_mode                     = "provisioned"
  engine_version                  = data.aws_rds_engine_version.mysql.version_actual
  database_name                   = "demo"
  master_username                 = "clusteradmin"
  manage_master_user_password     = true
  port                            = 3306
  db_subnet_group_name            = aws_db_subnet_group.this.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name
  vpc_security_group_ids          = [aws_security_group.tier["db"].id]
  storage_encrypted               = true
  backup_retention_period         = 7
  preferred_backup_window         = "17:00-18:00"
  preferred_maintenance_window    = "sun:18:00-sun:19:00"
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.skip_final_snapshot
  final_snapshot_identifier       = coalesce(var.final_snapshot_identifier, "${var.name}-final")
  copy_tags_to_snapshot           = true
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  # Do not pin cluster availability_zones to only two: Aurora storage spans three AZs.
}
resource "aws_rds_cluster_instance" "writer" {
  identifier                 = "${var.name}-instance-a"
  cluster_identifier         = aws_rds_cluster.this.id
  engine                     = aws_rds_cluster.this.engine
  engine_version             = aws_rds_cluster.this.engine_version
  instance_class             = var.db_instance_class
  availability_zone          = local.azs.a
  db_subnet_group_name       = aws_db_subnet_group.this.name
  publicly_accessible        = false
  auto_minor_version_upgrade = true
  promotion_tier             = 0
  tags                       = { Name = "${var.name}-initial-writer" }
}
resource "aws_rds_cluster_instance" "reader" {
  identifier                 = "${var.name}-instance-b"
  cluster_identifier         = aws_rds_cluster.this.id
  engine                     = aws_rds_cluster.this.engine
  engine_version             = aws_rds_cluster.this.engine_version
  instance_class             = var.db_instance_class
  availability_zone          = local.azs.b
  db_subnet_group_name       = aws_db_subnet_group.this.name
  publicly_accessible        = false
  auto_minor_version_upgrade = true
  promotion_tier             = 1
  tags                       = { Name = "${var.name}-initial-reader" }
  # Create the first instance before the second so initial roles match the diagram.
  depends_on = [aws_rds_cluster_instance.writer]
}
