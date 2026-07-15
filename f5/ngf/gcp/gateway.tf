resource "kubectl_manifest" "gateway" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = local.gateway_name
      namespace = kubernetes_namespace.nginx_gateway.metadata[0].name
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
        owner                          = local.resource_owner
      }
    }
    spec = {
      gatewayClassName = var.gatewayclass_name
      listeners = [
        {
          name     = "http"
          port     = 80
          protocol = "HTTP"
          allowedRoutes = {
            namespaces = { from = "All" }
          }
        },
      ]
    }
  })

  depends_on = [helm_release.ngf]
}

# The data plane Service and its LoadBalancer IP are provisioned asynchronously
# after the Gateway is accepted. Give the control plane and GCP time to assign it.
resource "time_sleep" "wait_dataplane" {
  depends_on      = [kubectl_manifest.gateway]
  create_duration = "180s"
}

data "kubernetes_service_v1" "dataplane" {
  metadata {
    name      = local.dataplane_service_name
    namespace = kubernetes_namespace.nginx_gateway.metadata[0].name
  }

  depends_on = [time_sleep.wait_dataplane]
}
