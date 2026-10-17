resource "aws_security_group" "tier" {
  for_each    = toset(["external-alb", "web", "internal-alb", "app", "db"])
  name_prefix = "${var.name}-${each.key}-"
  description = "Traffic boundary for ${each.key}; rules managed separately"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-${each.key}" }
  lifecycle { create_before_destroy = true }
}
resource "aws_vpc_security_group_ingress_rule" "public_http" {
  for_each          = var.allowed_client_cidrs
  security_group_id = aws_security_group.tier["external-alb"].id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "Approved clients: HTTP demo or HTTPS redirect"
}
resource "aws_vpc_security_group_ingress_rule" "public_https" {
  for_each          = var.certificate_arn == null ? toset([]) : var.allowed_client_cidrs
  security_group_id = aws_security_group.tier["external-alb"].id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "Approved clients: HTTPS"
}
locals {
  tier_flows = {
    external_to_web = { from = "external-alb", to = "web", port = 80 }
    web_to_internal = { from = "web", to = "internal-alb", port = 80 }
    internal_to_app = { from = "internal-alb", to = "app", port = 3000 }
    app_to_db       = { from = "app", to = "db", port = 3306 }
  }
}
resource "aws_vpc_security_group_ingress_rule" "tier" {
  for_each                     = local.tier_flows
  security_group_id            = aws_security_group.tier[each.value.to].id
  referenced_security_group_id = aws_security_group.tier[each.value.from].id
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  description                  = each.key
}
resource "aws_vpc_security_group_egress_rule" "tier" {
  for_each                     = local.tier_flows
  security_group_id            = aws_security_group.tier[each.value.from].id
  referenced_security_group_id = aws_security_group.tier[each.value.to].id
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  description                  = each.key
}
resource "aws_vpc_security_group_egress_rule" "bootstrap_https" {
  for_each          = toset(["web", "app"])
  security_group_id = aws_security_group.tier[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS only: AL2023/npm repositories, S3, SSM, Secrets Manager"
}
