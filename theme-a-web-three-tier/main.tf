locals {
  azs = { a = var.availability_zones[0], b = var.availability_zones[1] }
  # Stable, non-overlapping subnet allocation derived from the supplied VPC CIDR.
  public_cidrs = { a = cidrsubnet(var.vpc_cidr, 4, 0), b = cidrsubnet(var.vpc_cidr, 4, 1) }
  app_cidrs    = { a = cidrsubnet(var.vpc_cidr, 4, 2), b = cidrsubnet(var.vpc_cidr, 4, 3) }
  db_cidrs     = { a = cidrsubnet(var.vpc_cidr, 4, 4), b = cidrsubnet(var.vpc_cidr, 4, 5) }
  ami_id       = var.ami_id != null ? var.ami_id : nonsensitive(data.aws_ssm_parameter.al2023[0].value)
  tiers = {
    web = { instance_type = var.web_instance_type, public_ip = true, port = 80 }
    app = { instance_type = var.app_instance_type, public_ip = false, port = 3000 }
  }
}

data "aws_partition" "current" {}
data "aws_ssm_parameter" "al2023" {
  count = var.ami_id == null ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
data "aws_rds_engine_version" "mysql" {
  engine                 = "aurora-mysql"
  parameter_group_family = "aurora-mysql8.0"
  version                = var.db_engine_version
  latest                 = var.db_engine_version == null
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name }
}
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}
resource "aws_subnet" "public" {
  for_each                = local.azs
  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value
  cidr_block              = local.public_cidrs[each.key]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name}-public-${each.key}", Tier = "web" }
}
resource "aws_subnet" "app" {
  for_each          = local.azs
  vpc_id            = aws_vpc.this.id
  availability_zone = each.value
  cidr_block        = local.app_cidrs[each.key]
  tags              = { Name = "${var.name}-app-${each.key}", Tier = "app" }
}
resource "aws_subnet" "db" {
  for_each          = local.azs
  vpc_id            = aws_vpc.this.id
  availability_zone = each.value
  cidr_block        = local.db_cidrs[each.key]
  tags              = { Name = "${var.name}-db-${each.key}", Tier = "db" }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-public" }
}
resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}
resource "aws_route_table_association" "public" {
  for_each       = local.azs
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}
resource "aws_eip" "nat" {
  for_each = local.azs
  domain   = "vpc"
  tags     = { Name = "${var.name}-nat-${each.key}" }
}
resource "aws_nat_gateway" "this" {
  for_each      = local.azs
  subnet_id     = aws_subnet.public[each.key].id
  allocation_id = aws_eip.nat[each.key].id
  tags          = { Name = "${var.name}-nat-${each.key}" }
  depends_on    = [aws_internet_gateway.this]
}
resource "aws_route_table" "app" {
  for_each = local.azs
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${var.name}-app-${each.key}" }
}
resource "aws_route" "app_nat" {
  for_each               = local.azs
  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}
resource "aws_route_table_association" "app" {
  for_each       = local.azs
  subnet_id      = aws_subnet.app[each.key].id
  route_table_id = aws_route_table.app[each.key].id
}
# Isolated DB subnets: local VPC route only, no NAT / Internet Gateway default route.
resource "aws_route_table" "db" {
  for_each = local.azs
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${var.name}-db-${each.key}" }
}
resource "aws_route_table_association" "db" {
  for_each       = local.azs
  subnet_id      = aws_subnet.db[each.key].id
  route_table_id = aws_route_table.db[each.key].id
}
