variable "region" {
  type    = string
  default = "ap-northeast-1"
}
variable "name" {
  type    = string
  default = "retail-demo"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.name))
    error_message = "Use 3-21 lowercase letters, digits or hyphens, starting with a letter."
  }
}
variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && can(cidrsubnet(var.vpc_cidr, 8, 21)) && try(tonumber(split("/", var.vpc_cidr)[1]) <= 20, false)
    error_message = "Supply an IPv4 network that supports at least 22 subnets using 8 additional bits."
  }
}
variable "admin_principal_arn" {
  description = "IAM role/user ARN for the operator running stages 02 and 03. Do not use an STS assumed-role ARN."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:(role|user)/.+$", var.admin_principal_arn))
    error_message = "Use an IAM role/user ARN, not an STS session ARN."
  }
}
variable "admin_cidrs" {
  description = "Public IPv4 egress CIDRs of Terraform/kubectl operators. Also account for VPN egress."
  type        = list(string)
  validation {
    condition     = length(var.admin_cidrs) > 0 && alltrue([for c in var.admin_cidrs : can(cidrnetmask(c)) && c != "0.0.0.0/0"])
    error_message = "Provide operator IPv4 CIDRs; 0.0.0.0/0 is intentionally disallowed."
  }
}
variable "client_cidrs" {
  description = "Allowed IPv4 sources for the sample store ALB. Set 0.0.0.0/0 only if deliberate public exposure is acceptable."
  type        = list(string)
  validation {
    condition     = length(var.client_cidrs) > 0 && alltrue([for c in var.client_cidrs : can(cidrnetmask(c))])
    error_message = "Provide at least one valid IPv4 CIDR."
  }
}
variable "kubernetes_version" {
  type    = string
  default = "1.35"
}
variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}
variable "node_desired_size" {
  type    = number
  default = 2
}
variable "node_max_size" {
  type    = number
  default = 4
}
variable "single_nat_gateway" {
  description = "true saves cost but introduces a single-AZ dependency and cross-AZ traffic."
  type        = bool
  default     = true
}
variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}
variable "db_multi_az" {
  type    = bool
  default = false
}
variable "mysql_engine_version" {
  type    = string
  default = "8.0"
  validation {
    condition     = can(regex("^8\\.0(\\.[0-9]+)?$", var.mysql_engine_version))
    error_message = "This example uses the mysql8.0 parameter family; select an 8.0 version."
  }
}
variable "postgres_engine_version" {
  type    = string
  default = "16"
  validation {
    condition     = can(regex("^16(\\.[0-9]+)?$", var.postgres_engine_version))
    error_message = "This example uses the postgres16 parameter family; select a 16 version."
  }
}
variable "redis_node_type" {
  type    = string
  default = "cache.t4g.micro"
}
variable "deletion_protection" {
  description = "RDS and DynamoDB protection. Turn off and apply before destroying."
  type        = bool
  default     = true
}
variable "skip_final_snapshot" {
  description = "false keeps a billable final RDS snapshot."
  type        = bool
  default     = false
}
variable "final_snapshot_suffix" {
  description = "Choose a unique suffix before destroy; existing snapshot names cannot be reused."
  type        = string
  default     = "final-001"
}
