terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "= 6.68.0" }
  }
}
provider "aws" {
  region = var.region
  default_tags { tags = { Project = var.name, ManagedBy = "Terraform", Example = "theme-b" } }
}
data "aws_availability_zones" "available" { state = "available" }
data "aws_partition" "current" {}
locals {
  azs       = slice(data.aws_availability_zones.available.names, 0, 2)
  az_map    = { for i, az in local.azs : tostring(i) => az }
  namespace = "retail"
}
