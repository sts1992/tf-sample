variable "name" {
  description = "Lowercase resource prefix. Use a different value for every deployment."
  type        = string
  default     = "theme-a"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,18}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be 2–20 lowercase letters, digits or hyphens, start with a letter, end with a letter/digit, and have no consecutive hyphens."
  }
}
variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}
variable "availability_zones" {
  description = "Exactly two distinct AZ names in aws_region. Keep stable after deployment."
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
  validation {
    condition     = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
    error_message = "Specify exactly two distinct Availability Zones."
  }
}
variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && try(tonumber(split("/", var.vpc_cidr)[1]) <= 20, false)
    error_message = "Use an IPv4 CIDR with prefix length at most /20; six /24-or-larger subnets are derived automatically."
  }
}
variable "allowed_client_cidrs" {
  description = "IPv4 source networks allowed to reach the public ALB; set your real public IP /32. Unrestricted /0 is rejected because this demo has no authentication."
  type        = set(string)
  validation {
    condition     = length(var.allowed_client_cidrs) > 0 && alltrue([for c in var.allowed_client_cidrs : can(cidrnetmask(c)) && try(tonumber(split("/", c)[1]) > 0, false)])
    error_message = "Supply at least one valid, restricted IPv4 CIDR (prefer your public IP /32). Unrestricted /0 access is not allowed."
  }
}
variable "certificate_arn" {
  description = "Existing ACM certificate in this region. Null requires explicit allow_insecure_http for a temporary HTTP-only demo."
  type        = string
  default     = null
  nullable    = true
}
variable "allow_insecure_http" {
  description = "Explicit opt-in for a temporary, CIDR-restricted HTTP demo without an ACM certificate. Never use with sensitive data."
  type        = bool
  default     = false
}
variable "ami_id" {
  description = "Optional pinned Amazon Linux 2023 x86_64 AMI; null resolves the public AWS SSM latest AMI parameter."
  type        = string
  default     = null
}
variable "web_instance_type" {
  type    = string
  default = "t3.small"
}
variable "app_instance_type" {
  type    = string
  default = "t3.small"
}
variable "asg_capacity" {
  description = "Capacity applied separately to web and app; minimum two is required for the two-AZ example."
  type        = object({ min = number, desired = number, max = number })
  default     = { min = 2, desired = 2, max = 4 }
  validation {
    condition     = var.asg_capacity.min >= 2 && var.asg_capacity.min <= var.asg_capacity.desired && var.asg_capacity.desired <= var.asg_capacity.max && alltrue([for n in values(var.asg_capacity) : n == floor(n)])
    error_message = "Capacity must be integers satisfying 2 <= min <= desired <= max."
  }
}
variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}
variable "db_engine_version" {
  description = "Optional exact Aurora MySQL 3 version. Null resolves the latest available version in the MySQL 8.0 family at plan time. Pin after the first reviewed plan."
  type        = string
  default     = null
}
variable "deletion_protection" {
  description = "Protect both ALBs and Aurora from accidental deletion. Set false and apply before destroy."
  type        = bool
  default     = true
}
variable "skip_final_snapshot" {
  description = "False preserves a final Aurora snapshot on deletion. True is only suitable for disposable data."
  type        = bool
  default     = false
}
variable "final_snapshot_identifier" {
  description = "Optional unique name for final snapshot. Default is <name>-final; change it if a snapshot with that name exists."
  type        = string
  default     = null
}
variable "tags" {
  type    = map(string)
  default = { Environment = "training" }
}
