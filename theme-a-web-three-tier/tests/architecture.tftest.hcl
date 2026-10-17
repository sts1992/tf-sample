# These tests mock ALL AWS operations. They never create or inspect AWS resources.
mock_provider "aws" {
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_ssm_parameter" { defaults = { value = "ami-0123456789abcdef0" } }
  mock_data "aws_rds_engine_version" { defaults = { version_actual = "8.0.mysql_aurora.3.10.2" } }
}
variables {
  allowed_client_cidrs = ["203.0.113.10/32"]
  allow_insecure_http  = true
}
run "two_az_security_baseline" {
  command = plan
  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.app) == 2 && length(aws_subnet.db) == 2 && length(aws_nat_gateway.this) == 2
    error_message = "The diagram requires six subnets and two NAT gateways across two AZs."
  }
  assert {
    condition     = aws_lb.internal.internal && !aws_lb.external.internal
    error_message = "Only the external ALB may be internet-facing."
  }
  assert {
    condition     = alltrue([for g in aws_autoscaling_group.tier : g.min_size >= 2 && g.health_check_type == "ELB"])
    error_message = "Both ASGs need at least two instances and ELB health checks."
  }
  assert {
    condition     = aws_rds_cluster.this.manage_master_user_password && aws_rds_cluster.this.storage_encrypted && aws_rds_cluster.this.deletion_protection && !aws_rds_cluster.this.skip_final_snapshot
    error_message = "Aurora must use managed credentials, encryption and deletion safeguards."
  }
  assert {
    condition     = !aws_rds_cluster_instance.writer.publicly_accessible && !aws_rds_cluster_instance.reader.publicly_accessible && aws_rds_cluster_instance.writer.availability_zone != aws_rds_cluster_instance.reader.availability_zone
    error_message = "Database instances must be private and in separate AZs."
  }
  assert {
    condition     = alltrue([for lt in aws_launch_template.tier : lt.metadata_options[0].http_tokens == "required" && alltrue([for disk in lt.block_device_mappings : disk.ebs[0].encrypted])])
    error_message = "All EC2s must use IMDSv2 and encrypted EBS."
  }
  assert {
    condition     = length(aws_lb_listener.https) == 0 && aws_lb_listener.http.default_action[0].type == "forward"
    error_message = "No certificate means the explicitly documented HTTP demo mode."
  }
  assert {
    condition     = toset([for source in data.archive_file.demo["web"].source : source.filename]) == toset(["app.jsx", "index.html", "package.json", "package-lock.json"]) && toset([for source in data.archive_file.demo["app"].source : source.filename]) == toset(["handler.mjs", "server.mjs", "package.json", "package-lock.json"])
    error_message = "Artifacts must contain only reviewed demo files, never local credentials or arbitrary directory contents."
  }
}
run "optional_https" {
  command = plan
  variables {
    certificate_arn     = "arn:aws:acm:ap-northeast-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    allow_insecure_http = false
  }
  assert {
    condition     = length(aws_lb_listener.https) == 1 && aws_lb_listener.http.default_action[0].type == "redirect"
    error_message = "A supplied ACM certificate must enable HTTPS and redirect HTTP."
  }
}
run "reject_implicit_http" {
  command = plan
  variables { allow_insecure_http = false }
  expect_failures = [aws_lb_listener.http]
}
run "reject_single_az" {
  command = plan
  variables { availability_zones = ["ap-northeast-1a", "ap-northeast-1a"] }
  expect_failures = [var.availability_zones]
}
run "reject_insufficient_capacity" {
  command = plan
  variables { asg_capacity = { min = 1, desired = 1, max = 2 } }
  expect_failures = [var.asg_capacity]
}
run "reject_unrestricted_clients" {
  command = plan
  variables { allowed_client_cidrs = ["0.0.0.0/0"] }
  expect_failures = [var.allowed_client_cidrs]
}
run "reject_unrestricted_clients_with_host_bits" {
  command = plan
  variables { allowed_client_cidrs = ["203.0.113.10/0"] }
  expect_failures = [var.allowed_client_cidrs]
}
run "reject_invalid_client_cidr" {
  command = plan
  variables { allowed_client_cidrs = ["not-a-cidr"] }
  expect_failures = [var.allowed_client_cidrs]
}
run "reject_ipv6_clients" {
  command = plan
  variables { allowed_client_cidrs = ["::/0"] }
  expect_failures = [var.allowed_client_cidrs]
}
run "reject_empty_clients" {
  command = plan
  variables { allowed_client_cidrs = [] }
  expect_failures = [var.allowed_client_cidrs]
}
