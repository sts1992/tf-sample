locals {
  user_data = {
    web = templatefile("${path.module}/templates/web.sh.tftpl", {
      region        = var.aws_region
      artifact_uri  = "s3://${aws_s3_bucket.artifacts.id}/${aws_s3_object.demo["web"].key}"
      internal_host = aws_lb.internal.dns_name
      resolver      = cidrhost(var.vpc_cidr, 2)
    })
    app = templatefile("${path.module}/templates/app.sh.tftpl", {
      region       = var.aws_region
      artifact_uri = "s3://${aws_s3_bucket.artifacts.id}/${aws_s3_object.demo["app"].key}"
      secret_arn   = aws_rds_cluster.this.master_user_secret[0].secret_arn
      writer_host  = aws_rds_cluster.this.endpoint
      reader_host  = aws_rds_cluster.this.reader_endpoint
    })
  }
}
resource "aws_launch_template" "tier" {
  for_each               = local.tiers
  name_prefix            = "${var.name}-${each.key}-"
  image_id               = local.ami_id
  instance_type          = each.value.instance_type
  update_default_version = true
  user_data              = base64encode(local.user_data[each.key])
  iam_instance_profile { name = aws_iam_instance_profile.ec2[each.key].name }
  network_interfaces {
    device_index                = 0
    associate_public_ip_address = each.value.public_ip
    security_groups             = [aws_security_group.tier[each.key].id]
    delete_on_termination       = true
  }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 16
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }
  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name}-${each.key}", Project = var.name, Tier = each.key, ManagedBy = "Terraform" })
  }
  lifecycle {
    create_before_destroy = true
    precondition {
      condition     = length(local.user_data[each.key]) < 16384
      error_message = "EC2 raw user-data must be less than 16 KiB."
    }
  }
}
resource "aws_autoscaling_group" "tier" {
  for_each                  = local.tiers
  name                      = "${var.name}-${each.key}"
  min_size                  = var.asg_capacity.min
  desired_capacity          = var.asg_capacity.desired
  max_size                  = var.asg_capacity.max
  vpc_zone_identifier       = each.key == "web" ? [for s in aws_subnet.public : s.id] : [for s in aws_subnet.app : s.id]
  target_group_arns         = [aws_lb_target_group.tier[each.key].arn]
  health_check_type         = "ELB"
  health_check_grace_period = 600
  default_instance_warmup   = 180
  wait_for_capacity_timeout = "20m"
  min_elb_capacity          = var.asg_capacity.min
  launch_template {
    id      = aws_launch_template.tier[each.key].id
    version = aws_launch_template.tier[each.key].latest_version
  }
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 150
      instance_warmup        = 180
    }
  }
  tag {
    key                 = "Name"
    value               = "${var.name}-${each.key}"
    propagate_at_launch = true
  }
  lifecycle { ignore_changes = [desired_capacity] }
  depends_on = [
    aws_route.internet, aws_route.app_nat, aws_route_table_association.public, aws_route_table_association.app,
    aws_iam_role_policy.artifact, aws_iam_role_policy.database_secret, aws_iam_role_policy_attachment.ssm,
    aws_s3_bucket_policy.artifacts, aws_lb_listener.http, aws_lb_listener.https, aws_lb_listener.internal,
    aws_vpc_security_group_ingress_rule.tier, aws_vpc_security_group_egress_rule.tier,
    aws_vpc_security_group_egress_rule.bootstrap_https, aws_rds_cluster_instance.reader
  ]
}
resource "aws_autoscaling_policy" "cpu" {
  for_each               = local.tiers
  name                   = "${var.name}-${each.key}-cpu"
  autoscaling_group_name = aws_autoscaling_group.tier[each.key].name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification { predefined_metric_type = "ASGAverageCPUUtilization" }
    target_value = 60
  }
}
