resource "kubernetes_secret" "nginx_license" {
  metadata {
    name      = local.license_secret_name
    namespace = kubernetes_namespace.nginx_gateway.metadata[0].name
  }

  type = "Opaque"

  data = {
    "license.jwt" = var.nginx_jwt
  }
}

resource "kubernetes_secret" "registry" {
  metadata {
    name      = local.regcred_secret_name
    namespace = kubernetes_namespace.nginx_gateway.metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (var.nginx_registry) = {
          username = var.nginx_jwt
          password = "none"
          auth     = base64encode("${var.nginx_jwt}:none")
        }
      }
    })
  }
}
