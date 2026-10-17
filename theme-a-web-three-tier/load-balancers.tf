resource "aws_lb" "external" {
  name                       = "${var.name}-public"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.tier["external-alb"].id]
  subnets                    = [for s in aws_subnet.public : s.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection
}
resource "aws_lb" "internal" {
  name                       = "${var.name}-internal"
  internal                   = true
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.tier["internal-alb"].id]
  subnets                    = [for s in aws_subnet.app : s.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection
}
resource "aws_lb_target_group" "tier" {
  for_each             = local.tiers
  name_prefix          = each.key == "web" ? "web-" : "app-"
  port                 = each.value.port
  protocol             = "HTTP"
  target_type          = "instance"
  vpc_id               = aws_vpc.this.id
  deregistration_delay = 30
  health_check {
    path                = "/healthz"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }
  lifecycle { create_before_destroy = true }
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.external.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = var.certificate_arn == null ? "forward" : "redirect"
    target_group_arn = var.certificate_arn == null ? aws_lb_target_group.tier["web"].arn : null
    dynamic "redirect" {
      for_each = var.certificate_arn == null ? [] : [1]
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}
resource "aws_lb_listener" "https" {
  count             = var.certificate_arn == null ? 0 : 1
  load_balancer_arn = aws_lb.external.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tier["web"].arn
  }
}
resource "aws_lb_listener" "internal" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tier["app"].arn
  }
}
