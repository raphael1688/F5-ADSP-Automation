resource "kubectl_manifest" "virtualserver" {
  yaml_body = yamlencode({
    apiVersion = "k8s.nginx.org/v1"
    kind       = "VirtualServer"
    metadata = {
      name      = local.release_name
      namespace = kubernetes_namespace.app.metadata[0].name
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
        owner                          = local.resource_owner
      }
    }
    spec = merge(
      {
        ingressClassName = "nginx"
        host             = var.app_host
        upstreams = [
          {
            name    = "api"
            service = local.api_service_name
            port    = local.api_service_port
          },
          {
            name    = "frontend"
            service = local.frontend_service_name
            port    = local.frontend_service_port
          },
        ]
        routes = [
          merge(
            {
              path = "/api/"
              action = {
                proxy = {
                  upstream    = "api"
                  rewritePath = "/"
                }
              }
            },
            length(local.api_route_policies) > 0 ? { policies = local.api_route_policies } : {},
          ),
          {
            path = "/"
            action = {
              pass = "frontend"
            }
          },
        ]
      },
      length(local.server_wide_policies) > 0 ? { policies = local.server_wide_policies } : {},
      var.vs_tls_enabled ? { tls = { secret = var.vs_tls_secret_name } } : {},
    )
  })

  depends_on = [helm_release.comfy_capybara]
}
