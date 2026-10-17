# Policies are additive. Only these paths are permitted after VPC CNI policy convergence.
# kube-system is deliberately untouched: node-side CSI, image pulls and control-plane traffic
# do not originate from retail application Pods. Do not use this as a node isolation boundary.
locals {
  app_callers = {
    catalog  = ["ui"]
    carts    = ["ui"]
    checkout = ["ui"]
    orders   = ["ui", "checkout"]
  }
  app_destinations = {
    ui       = ["catalog", "carts", "checkout", "orders"]
    checkout = ["orders"]
  }
  data_ports = { catalog = 3306, orders = 5432, checkout = 6379 }
}

resource "kubernetes_network_policy_v1" "default_deny" {
  metadata {
    name      = "default-deny"
    namespace = kubernetes_namespace_v1.retail.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy_v1" "dns" {
  metadata {
    name      = "allow-coredns"
    namespace = kubernetes_namespace_v1.retail.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Egress"]
    egress {
      to {
        namespace_selector { match_labels = { "kubernetes.io/metadata.name" = "kube-system" } }
        pod_selector { match_labels = { "k8s-app" = "kube-dns" } }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "app_ingress" {
  for_each = local.app_callers
  metadata {
    name      = "${each.key}-ingress"
    namespace = kubernetes_namespace_v1.retail.metadata[0].name
  }
  spec {
    pod_selector { match_labels = { app = each.key } }
    policy_types = ["Ingress"]
    ingress {
      dynamic "from" {
        for_each = each.value
        content {
          pod_selector { match_labels = { app = from.value } }
        }
      }
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "ui_ingress" {
  metadata {
    name      = "ui-from-alb-subnets"
    namespace = kubernetes_namespace_v1.retail.metadata[0].name
  }
  spec {
    pod_selector { match_labels = { app = "ui" } }
    policy_types = ["Ingress"]
    ingress {
      # ALB terminates the client connection; the backend source is its private subnet IP.
      # The node SG additionally restricts this to the ALB SG, rather than every subnet host.
      dynamic "from" {
        for_each = local.infra.public_subnet_cidrs
        content {
          ip_block { cidr = from.value }
        }
      }
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "app_egress" {
  for_each = local.app_destinations
  metadata {
    name      = "${each.key}-app-egress"
    namespace = kubernetes_namespace_v1.retail.metadata[0].name
  }
  spec {
    pod_selector { match_labels = { app = each.key } }
    policy_types = ["Egress"]
    egress {
      dynamic "to" {
        for_each = each.value
        content {
          pod_selector { match_labels = { app = to.value } }
        }
      }
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "data_egress" {
  for_each = local.data_ports
  metadata {
    name      = "${each.key}-data-egress"
    namespace = kubernetes_namespace_v1.retail.metadata[0].name
  }
  spec {
    pod_selector { match_labels = { app = each.key } }
    policy_types = ["Egress"]
    egress {
      # RDS/Redis addresses change during failover; scope to isolated data subnets and port.
      dynamic "to" {
        for_each = local.infra.data_subnet_cidrs
        content {
          ip_block { cidr = to.value }
        }
      }
      ports {
        port     = tostring(each.value)
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "aws_https" {
  for_each = toset(["carts", "orders"])
  metadata {
    name      = "${each.key}-aws-https"
    namespace = kubernetes_namespace_v1.retail.metadata[0].name
  }
  spec {
    pod_selector { match_labels = { app = each.key } }
    policy_types = ["Egress"]
    egress {
      # Regional STS, SQS and DynamoDB use public IPs (including the DDB gateway endpoint).
      # NetworkPolicy cannot identify AWS DNS names. IAM remains the authorization boundary.
      to {
        ip_block {
          cidr   = "0.0.0.0/0"
          except = [local.infra.vpc_cidr, "169.254.0.0/16"]
        }
      }
      ports {
        port     = "443"
        protocol = "TCP"
      }
    }
  }
}
