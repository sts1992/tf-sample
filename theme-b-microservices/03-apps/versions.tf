terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "= 3.3.0" }
  }
}
data "terraform_remote_state" "infra" {
  backend = "local"
  config  = { path = abspath("${path.module}/${var.infra_state_path}") }
}
data "terraform_remote_state" "platform" {
  backend = "local"
  config  = { path = abspath("${path.module}/${var.platform_state_path}") }
}
locals {
  infra     = data.terraform_remote_state.infra.outputs.deployment
  namespace = local.infra.namespace
}
provider "kubernetes" {
  host                   = local.infra.cluster_endpoint
  cluster_ca_certificate = base64decode(local.infra.cluster_ca)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--region", local.infra.region, "--cluster-name", local.infra.name]
  }
}
