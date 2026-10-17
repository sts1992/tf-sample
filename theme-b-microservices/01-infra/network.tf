resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name }
}
resource "aws_internet_gateway" "this" { vpc_id = aws_vpc.this.id }
resource "aws_subnet" "public" {
  for_each          = local.az_map
  vpc_id            = aws_vpc.this.id
  availability_zone = each.value
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, tonumber(each.key))
  tags              = { Name = "${var.name}-public-${each.key}", "kubernetes.io/role/elb" = "1" }
}
resource "aws_subnet" "app" {
  for_each          = local.az_map
  vpc_id            = aws_vpc.this.id
  availability_zone = each.value
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 10 + tonumber(each.key))
  tags              = { Name = "${var.name}-app-${each.key}", "kubernetes.io/role/internal-elb" = "1" }
}
resource "aws_subnet" "data" {
  for_each          = local.az_map
  vpc_id            = aws_vpc.this.id
  availability_zone = each.value
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 20 + tonumber(each.key))
  tags              = { Name = "${var.name}-data-${each.key}" }
}
resource "aws_route_table" "public" { vpc_id = aws_vpc.this.id }
resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}
resource "aws_route_table_association" "public" {
  for_each       = local.az_map
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}
resource "aws_eip" "nat" {
  for_each = var.single_nat_gateway ? { "0" = local.azs[0] } : local.az_map
  domain   = "vpc"
}
resource "aws_nat_gateway" "this" {
  for_each      = aws_eip.nat
  allocation_id = each.value.id
  subnet_id     = aws_subnet.public[each.key].id
  depends_on    = [aws_internet_gateway.this]
}
resource "aws_route_table" "app" {
  for_each = local.az_map
  vpc_id   = aws_vpc.this.id
}
resource "aws_route" "nat" {
  for_each               = local.az_map
  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? "0" : each.key].id
}
resource "aws_route_table_association" "app" {
  for_each       = local.az_map
  subnet_id      = aws_subnet.app[each.key].id
  route_table_id = aws_route_table.app[each.key].id
}
# Data subnets deliberately have no default route to the Internet/NAT.
resource "aws_route_table" "data" { vpc_id = aws_vpc.this.id }
resource "aws_route_table_association" "data" {
  for_each       = local.az_map
  subnet_id      = aws_subnet.data[each.key].id
  route_table_id = aws_route_table.data.id
}
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in aws_route_table.app : rt.id]
}
resource "aws_security_group" "nodes" {
  name_prefix = "${var.name}-nodes-"
  vpc_id      = aws_vpc.this.id
  tags        = { "kubernetes.io/cluster/${var.name}" = "owned" }
}
resource "aws_vpc_security_group_ingress_rule" "nodes_self" {
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "-1"
}
resource "aws_vpc_security_group_egress_rule" "nodes" {
  security_group_id = aws_security_group.nodes.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  vpc_id      = aws_vpc.this.id
}
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each          = toset(var.client_cidrs)
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each          = toset(var.client_cidrs)
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
resource "aws_vpc_security_group_egress_rule" "alb_app" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}
resource "aws_vpc_security_group_ingress_rule" "nodes_alb" {
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}
resource "aws_security_group" "data" {
  for_each    = { mysql = 3306, postgres = 5432, redis = 6379 }
  name_prefix = "${var.name}-${each.key}-"
  vpc_id      = aws_vpc.this.id
}
resource "aws_vpc_security_group_ingress_rule" "data" {
  for_each                     = { mysql = 3306, postgres = 5432, redis = 6379 }
  security_group_id            = aws_security_group.data[each.key].id
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
}
