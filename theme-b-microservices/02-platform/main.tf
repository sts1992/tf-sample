terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    helm = { source = "hashicorp/helm", version = "= 3.3.0" }
  }
}
variable "infra_state_path" {
  type    = string
  default = "../01-infra/terraform.tfstate"
}
data "terraform_remote_state" "infra" {
  backend = "local"
  config  = { path = abspath("${path.module}/${var.infra_state_path}") }
}
locals { infra = data.terraform_remote_state.infra.outputs.deployment }
provider "helm" {
  kubernetes = {
    host                   = local.infra.cluster_endpoint
    cluster_ca_certificate = base64decode(local.infra.cluster_ca)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--region", local.infra.region, "--cluster-name", local.infra.name]
    }
  }
}
resource "helm_release" "alb" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.6.0"
  atomic     = true
  wait       = true
  timeout    = 900
  values = [yamlencode({
    clusterName  = local.infra.name
    region       = local.infra.region
    vpcId        = local.infra.vpc_id
    replicaCount = 2
    serviceAccount = {
      create      = true
      name        = "aws-load-balancer-controller"
      annotations = { "eks.amazonaws.com/role-arn" = local.infra.pod_role_arns.alb }
    }
    enableServiceMutatorWebhook = false
    # This example uses Ingress only, not Gateway API.
    controllerConfig = { featureGates = { ALBGatewayAPI = false, NLBGatewayAPI = false } }
  })]
}
resource "helm_release" "secrets_csi" {
  name       = "secrets-store-csi-driver"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  version    = "1.6.1"
  atomic     = true
  wait       = true
  timeout    = 900
  values = [yamlencode({
    syncSecret           = { enabled = true }
    tokenRequests        = [{ audience = "sts.amazonaws.com" }, { audience = "pods.eks.amazonaws.com" }]
    enableSecretRotation = true
    rotationPollInterval = "2m"
  })]
}
resource "helm_release" "secrets_aws" {
  name       = "secrets-store-csi-driver-provider-aws"
  namespace  = "kube-system"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  version    = "3.1.4"
  atomic     = true
  wait       = true
  timeout    = 900
  values     = [yamlencode({ "secrets-store-csi-driver" = { install = false }, awsRegion = local.infra.region })]
  depends_on = [helm_release.secrets_csi]
}
output "ready" {
  value      = { cluster_name = local.infra.name }
  depends_on = [helm_release.alb, helm_release.secrets_csi, helm_release.secrets_aws]
}
