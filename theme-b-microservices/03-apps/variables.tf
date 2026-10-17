variable "infra_state_path" {
  type    = string
  default = "../01-infra/terraform.tfstate"
}
variable "platform_state_path" {
  type    = string
  default = "../02-platform/terraform.tfstate"
}
variable "image_tag" {
  description = "Verified against official v1.6.3 sources. Review env contracts before upgrading."
  type        = string
  default     = "1.6.3"
}
variable "replicas" {
  type    = number
  default = 1
  validation {
    condition     = var.replicas >= 1 && var.replicas == floor(var.replicas)
    error_message = "Use a positive integer."
  }
}
variable "certificate_arn" {
  description = "Optional ACM certificate ARN in the same region; empty means HTTP-only demo."
  type        = string
  default     = ""
}
variable "hostname" {
  description = "Optional hostname, required when using an ACM certificate. Create matching DNS separately."
  type        = string
  default     = ""
}
