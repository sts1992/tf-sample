resource "kubernetes_deployment_v1" "app" {
  for_each = local.apps
  metadata {
    name      = each.key
    namespace = kubernetes_namespace_v1.retail.metadata[0].name
    labels    = { app = each.key }
  }
  spec {
    replicas = var.replicas
    selector { match_labels = { app = each.key } }
    template {
      metadata { labels = { app = each.key } }
      spec {
        service_account_name            = kubernetes_service_account_v1.app[each.key].metadata[0].name
        automount_service_account_token = false
        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          fs_group        = 1000
          seccomp_profile { type = "RuntimeDefault" }
        }
        container {
          name              = each.key
          image             = "public.ecr.aws/aws-containers/retail-store-sample-${each.value.image}:${var.image_tag}"
          image_pull_policy = "IfNotPresent"
          port {
            name           = "http"
            container_port = 8080
          }
          dynamic "env" {
            for_each = merge(each.value.env, { AWS_REGION = local.infra.region, AWS_DEFAULT_REGION = local.infra.region, AWS_STS_REGIONAL_ENDPOINTS = "regional" })
            content {
              name  = env.key
              value = env.value
            }
          }
          dynamic "env_from" {
            for_each = contains(keys(local.db_secrets), each.key) ? [1] : []
            content {
              secret_ref { name = "${each.key}-db" }
            }
          }
          resources {
            requests = { cpu = each.value.cpu, memory = each.value.memory }
            limits   = { memory = each.value.memory }
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities { drop = ["ALL"] }
          }
          startup_probe {
            http_get {
              path = each.value.health
              port = 8080
            }
            failure_threshold = 60
            period_seconds    = 5
            timeout_seconds   = 3
          }
          readiness_probe {
            http_get {
              path = each.value.health
              port = 8080
            }
            period_seconds  = 10
            timeout_seconds = 3
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
          dynamic "volume_mount" {
            for_each = contains(keys(local.db_secrets), each.key) ? [1] : []
            content {
              name       = "db-secret"
              mount_path = "/mnt/secrets-store"
              read_only  = true
            }
          }
          dynamic "volume_mount" {
            for_each = each.key == "orders" ? [1] : []
            content {
              name       = "rds-ca"
              mount_path = "/etc/rds-ca"
              read_only  = true
            }
          }
        }
        volume {
          name = "tmp"
          empty_dir { medium = "Memory" }
        }
        dynamic "volume" {
          for_each = contains(keys(local.db_secrets), each.key) ? [1] : []
          content {
            name = "db-secret"
            csi {
              driver            = "secrets-store.csi.k8s.io"
              read_only         = true
              volume_attributes = { secretProviderClass = "${each.key}-db" }
            }
          }
        }
        dynamic "volume" {
          for_each = each.key == "orders" ? [1] : []
          content {
            name = "rds-ca"
            config_map { name = kubernetes_config_map_v1.rds_ca.metadata[0].name }
          }
        }
        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "topology.kubernetes.io/zone"
          when_unsatisfiable = "ScheduleAnyway"
          label_selector { match_labels = { app = each.key } }
        }
      }
    }
  }
  wait_for_rollout = true
  timeouts {
    create = "15m"
    update = "15m"
  }
  depends_on = [kubernetes_manifest.db_secrets, kubernetes_service_v1.app]
}
resource "kubernetes_service_v1" "app" {
  for_each = local.apps
  metadata {
    name      = each.key
    namespace = kubernetes_namespace_v1.retail.metadata[0].name
  }
  spec {
    type     = "ClusterIP"
    selector = { app = each.key }
    port {
      name        = "http"
      port        = 80
      target_port = 8080
    }
  }
}
resource "kubernetes_ingress_v1" "ui" {
  metadata {
    name      = "ui"
    namespace = kubernetes_namespace_v1.retail.metadata[0].name
    annotations = merge({
      "alb.ingress.kubernetes.io/scheme"                              = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"                         = "ip"
      "alb.ingress.kubernetes.io/subnets"                             = join(",", local.infra.public_subnet_ids)
      "alb.ingress.kubernetes.io/security-groups"                     = local.infra.alb_security_group_id
      "alb.ingress.kubernetes.io/manage-backend-security-group-rules" = "false"
      "alb.ingress.kubernetes.io/healthcheck-path"                    = "/actuator/health/readiness"
      "alb.ingress.kubernetes.io/success-codes"                       = "200"
      "alb.ingress.kubernetes.io/load-balancer-attributes"            = "deletion_protection.enabled=false"
      "alb.ingress.kubernetes.io/listen-ports"                        = var.certificate_arn == "" ? jsonencode([{ HTTP = 80 }]) : jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
      }, var.certificate_arn == "" ? {} : {
      "alb.ingress.kubernetes.io/certificate-arn" = var.certificate_arn
      "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
      "alb.ingress.kubernetes.io/ssl-policy"      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
    })
  }
  spec {
    ingress_class_name = "alb"
    rule {
      host = var.hostname == "" ? null : var.hostname
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.app["ui"].metadata[0].name
              port { number = 80 }
            }
          }
        }
      }
    }
  }
  wait_for_load_balancer = true
  lifecycle {
    precondition {
      condition     = var.certificate_arn == "" || var.hostname != ""
      error_message = "Set a hostname matching the ACM certificate and create its DNS record separately."
    }
  }
  depends_on = [kubernetes_deployment_v1.app]
}
output "store_url" {
  value = "${var.certificate_arn == "" ? "http" : "https"}://${var.hostname == "" ? try(kubernetes_ingress_v1.ui.status[0].load_balancer[0].ingress[0].hostname, "pending-see-kubectl") : var.hostname}"
}
