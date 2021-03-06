# Create a deployment for the service
resource "kubernetes_deployment" "this" {
  count = false == var.daemon_set ? 1 : 0

  lifecycle {
    ignore_changes = [spec.0.replicas]
  }

  metadata {
    name      = var.name
    namespace = var.namespace_name
  }

  spec {
    selector {
      match_labels = {
        app = var.name
      }
    }

    template {
      metadata {
        annotations = {
          "sidecar.istio.io/inject" = false
          "prometheus.io/port"      = "9102"
          "prometheus.io/scrape"    = true
        }

        labels = {
          terrafrom = "true",
          app       = var.name
        }
      }

      spec {
        service_account_name            = local.service_account_name
        automount_service_account_token = true
        restart_policy                  = "Always"

        volume {
          name = "stats-exporter-mapping-config"

          config_map {
            name = "${var.name}-config"

            items {
              key  = "exporterConfiguration"
              path = "mapping-config.yaml"
            }
          }
        }

        container {
          name              = "${var.name}-statsd-sink"
          image             = "${var.exporter_image}:${var.exporter_image_tag}"
          image_pull_policy = var.image_pull_policy

          args = [
            "-statsd.listen-address=:8125",
            "-statsd.mapping-config=/statsd-exporter/mapping-config.yaml",
          ]

          resources {
            requests {
              memory = var.resources_statsd_requests_memory
              cpu    = var.resources_statsd_requests_cpu
            }

            limits {
              memory = var.resources_statsd_limits_memory
              cpu    = var.resources_statsd_limits_cpu
            }
          }

          port {
            container_port = 9102
            name           = "metrics"
            protocol       = "TCP"
          }
          port {
            container_port = 8125
            name           = "listener"
            protocol       = "TCP"
          }

          volume_mount {
            mount_path = "/statsd-exporter/"
            name       = "stats-exporter-mapping-config"
            read_only  = true
          }
        }
        container {
          name                     = var.name
          image                    = "${var.ambassador_image}:${var.ambassador_image_tag}"
          image_pull_policy        = var.image_pull_policy
          termination_message_path = "/dev/termination-log"

          resources {
            requests {
              memory = var.resources_requests_memory
              cpu    = var.resources_requests_cpu
            }

            limits {
              memory = var.resources_limits_memory
              cpu    = var.resources_limits_cpu
            }
          }

          env {
            name  = "AMBASSADOR_ID"
            value = var.ambassador_id
          }

          env {
            name  = "AMBASSADOR_DEBUG"
            value = var.ambassador_debug
          }

          env {
            name  = "STATSD_ENABLED"
            value = true
          }

          env {
            name  = "STATSD_HOST"
            value = "localhost"
          }

          env {
            name  = "STATSD_PORT"
            value = 8125
          }

          env {
            name = "AMBASSADOR_NAMESPACE"

            value_from {
              field_ref {
                field_path = var.ambassador_namespace_name
              }
            }
          }

          port {
            name           = "http"
            container_port = 80
            protocol       = "TCP"
          }
          port {
            name           = "https"
            container_port = 443
            protocol       = "TCP"
          }
          port {
            name           = "admin"
            container_port = 8877
            protocol       = "TCP"
          }

          liveness_probe {
            initial_delay_seconds = 3
            success_threshold     = 1
            timeout_seconds       = 1

            http_get {
              path   = "/ambassador/v0/check_alive"
              port   = 8877
              scheme = "HTTP"
            }
          }

          readiness_probe {
            initial_delay_seconds = 3
            success_threshold     = 1
            timeout_seconds       = 1

            http_get {
              path   = "/ambassador/v0/check_ready"
              port   = 8877
              scheme = "HTTP"
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.this,
    kubernetes_service_account.this,
  ]
}

