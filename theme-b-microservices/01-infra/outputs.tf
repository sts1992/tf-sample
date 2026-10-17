output "deployment" {
  description = "Non-secret stage handover; master secret values are never read by Terraform."
  value = {
    region                = var.region
    name                  = var.name
    namespace             = local.namespace
    vpc_id                = aws_vpc.this.id
    public_subnet_ids     = [for s in aws_subnet.public : s.id]
    public_subnet_cidrs   = [for s in aws_subnet.public : s.cidr_block]
    data_subnet_cidrs     = [for s in aws_subnet.data : s.cidr_block]
    vpc_cidr              = aws_vpc.this.cidr_block
    alb_security_group_id = aws_security_group.alb.id
    cluster_endpoint      = aws_eks_cluster.this.endpoint
    cluster_ca            = aws_eks_cluster.this.certificate_authority[0].data
    pod_role_arns         = { for k, r in aws_iam_role.pod : k => r.arn }
    catalog_endpoint      = aws_db_instance.catalog.endpoint
    catalog_database      = aws_db_instance.catalog.db_name
    catalog_secret_arn    = aws_db_instance.catalog.master_user_secret[0].secret_arn
    orders_endpoint       = aws_db_instance.orders.endpoint
    orders_database       = aws_db_instance.orders.db_name
    orders_secret_arn     = aws_db_instance.orders.master_user_secret[0].secret_arn
    carts_table_name      = aws_dynamodb_table.carts.name
    redis_endpoint        = "${aws_elasticache_replication_group.checkout.primary_endpoint_address}:6379"
    orders_queue_url      = aws_sqs_queue.orders.url
  }
}
output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${var.name}"
}
