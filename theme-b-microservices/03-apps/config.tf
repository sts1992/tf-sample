locals {
  apps = {
    ui = {
      image = "ui", health = "/actuator/health/readiness", memory = "512Mi", cpu = "256m"
      env = {
        RETAIL_UI_ENDPOINTS_CATALOG  = "http://catalog:8080"
        RETAIL_UI_ENDPOINTS_CARTS    = "http://carts:8080"
        RETAIL_UI_ENDPOINTS_CHECKOUT = "http://checkout:8080"
        RETAIL_UI_ENDPOINTS_ORDERS   = "http://orders:8080"
        RETAIL_UI_SEARCH_ENABLED     = "false"
        JAVA_OPTS                    = "-XX:MaxRAMPercentage=75.0"
      }
    }
    catalog = {
      image = "catalog", health = "/health", memory = "256Mi", cpu = "128m"
      env = {
        RETAIL_CATALOG_PERSISTENCE_PROVIDER = "mysql"
        RETAIL_CATALOG_PERSISTENCE_ENDPOINT = local.infra.catalog_endpoint
        RETAIL_CATALOG_PERSISTENCE_DB_NAME  = local.infra.catalog_database
      }
    }
    carts = {
      image = "cart", health = "/actuator/health/readiness", memory = "512Mi", cpu = "256m"
      env = {
        RETAIL_CART_PERSISTENCE_PROVIDER              = "dynamodb"
        RETAIL_CART_PERSISTENCE_DYNAMODB_TABLE_NAME   = local.infra.carts_table_name
        RETAIL_CART_PERSISTENCE_DYNAMODB_CREATE_TABLE = "false"
        JAVA_OPTS                                     = "-XX:MaxRAMPercentage=75.0"
      }
    }
    checkout = {
      image = "checkout", health = "/health", memory = "256Mi", cpu = "128m"
      env = {
        RETAIL_CHECKOUT_PERSISTENCE_PROVIDER  = "redis"
        RETAIL_CHECKOUT_PERSISTENCE_REDIS_URL = "rediss://${local.infra.redis_endpoint}"
        RETAIL_CHECKOUT_ENDPOINTS_ORDERS      = "http://orders:8080"
      }
    }
    orders = {
      image = "orders", health = "/actuator/health/readiness", memory = "512Mi", cpu = "256m"
      env = {
        RETAIL_ORDERS_PERSISTENCE_PROVIDER = "postgres"
        RETAIL_ORDERS_PERSISTENCE_ENDPOINT = local.infra.orders_endpoint
        # Upstream interpolates name into the JDBC URL. PostgreSQL driver validates the server using this CA.
        RETAIL_ORDERS_PERSISTENCE_NAME    = "${local.infra.orders_database}?sslmode=verify-full&sslrootcert=/etc/rds-ca/global-bundle.pem"
        RETAIL_ORDERS_MESSAGING_PROVIDER  = "sqs"
        RETAIL_ORDERS_MESSAGING_SQS_TOPIC = local.infra.orders_queue_url
        JAVA_OPTS                         = "-XX:MaxRAMPercentage=75.0"
      }
    }
  }
  db_secrets = {
    catalog = {
      arn          = local.infra.catalog_secret_arn
      user_key     = "RETAIL_CATALOG_PERSISTENCE_USER"
      password_key = "RETAIL_CATALOG_PERSISTENCE_PASSWORD"
    }
    orders = {
      arn          = local.infra.orders_secret_arn
      user_key     = "RETAIL_ORDERS_PERSISTENCE_USERNAME"
      password_key = "RETAIL_ORDERS_PERSISTENCE_PASSWORD"
    }
  }
}
resource "kubernetes_namespace_v1" "retail" {
  metadata { name = local.namespace }
  lifecycle {
    precondition {
      condition     = data.terraform_remote_state.platform.outputs.ready.cluster_name == local.infra.name
      error_message = "Complete stage 02-platform for this EKS cluster before planning stage 03-apps."
    }
  }
}
resource "kubernetes_service_account_v1" "app" {
  for_each = local.apps
  metadata {
    name        = each.key
    namespace   = kubernetes_namespace_v1.retail.metadata[0].name
    annotations = contains(keys(local.infra.pod_role_arns), each.key) ? { "eks.amazonaws.com/role-arn" = local.infra.pod_role_arns[each.key] } : {}
  }
  automount_service_account_token = false
}
resource "kubernetes_config_map_v1" "rds_ca" {
  metadata {
    name      = "rds-ca"
    namespace = kubernetes_namespace_v1.retail.metadata[0].name
  }
  data = { "global-bundle.pem" = file("${path.module}/certs/global-bundle.pem") }
}
resource "kubernetes_manifest" "db_secrets" {
  for_each = local.db_secrets
  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata   = { name = "${each.key}-db", namespace = kubernetes_namespace_v1.retail.metadata[0].name }
    spec = {
      provider = "aws"
      parameters = {
        region = local.infra.region
        objects = yamlencode([{
          objectName = each.value.arn
          objectType = "secretsmanager"
          jmesPath = [
            { path = "username", objectAlias = "db-username" },
            { path = "password", objectAlias = "db-password" }
          ]
        }])
      }
      secretObjects = [{
        secretName = "${each.key}-db"
        type       = "Opaque"
        data = [
          { objectName = "db-username", key = each.value.user_key },
          { objectName = "db-password", key = each.value.password_key }
        ]
      }]
    }
  }
}
