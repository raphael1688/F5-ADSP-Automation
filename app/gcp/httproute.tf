resource "kubectl_manifest" "httproute" {
  count = var.route_type == "httproute" ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = local.release_name
      namespace = kubernetes_namespace.app.metadata[0].name
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
        owner                          = local.resource_owner
      }
    }
    spec = {
      parentRefs = [
        {
          name        = local.gateway_name
          namespace   = local.gateway_namespace
          sectionName = "http"
        },
      ]
      hostnames = [var.app_host]
      rules = [
        {
          matches = [
            { path = { type = "PathPrefix", value = "/api" } },
          ]
          filters = [
            {
              type = "URLRewrite"
              urlRewrite = {
                path = {
                  type               = "ReplacePrefixMatch"
                  replacePrefixMatch = "/"
                }
              }
            },
          ]
          backendRefs = [
            { name = local.api_service_name, port = local.api_service_port },
          ]
        },
        {
          matches = [
            { path = { type = "PathPrefix", value = "/" } },
          ]
          backendRefs = [
            { name = local.frontend_service_name, port = local.frontend_service_port },
          ]
        },
      ]
    }
  })

  depends_on = [helm_release.comfy_capybara]
}
