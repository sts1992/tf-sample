output "web_url" {
  description = "Demo URL. With ACM, use a DNS name covered by the certificate and point it to public_alb_dns_name."
  value       = "${var.certificate_arn == null ? "http" : "https"}://${aws_lb.external.dns_name}"
}
output "public_alb_dns_name" { value = aws_lb.external.dns_name }
output "internal_alb_dns_name" { value = aws_lb.internal.dns_name }
output "vpc_id" { value = aws_vpc.this.id }
output "subnet_ids" {
  value = {
    public = { for k, s in aws_subnet.public : k => s.id }
    app    = { for k, s in aws_subnet.app : k => s.id }
    db     = { for k, s in aws_subnet.db : k => s.id }
  }
}
output "autoscaling_group_names" { value = { for k, g in aws_autoscaling_group.tier : k => g.name } }
output "database_endpoints" {
  description = "Endpoint addresses only; no secret values are read by Terraform. Use writer for writes and reader for read-only traffic."
  value       = { writer = aws_rds_cluster.this.endpoint, reader = aws_rds_cluster.this.reader_endpoint }
}
output "selected_db_engine_version" { value = data.aws_rds_engine_version.mysql.version_actual }
output "selected_ami_id" { value = local.ami_id }
