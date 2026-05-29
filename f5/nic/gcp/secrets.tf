resource "kubernetes_secret" "nginx_license" {
  metadata {
    name      = local.license_secret_name
    namespace = kubernetes_namespace.nginx_ingress.metadata[0].name
  }

  type = "nginx.com/license"

  data = {
    "license.jwt" = var.nginx_jwt
  }
}

resource "kubernetes_secret" "registry" {
  metadata {
    name      = local.regcred_secret_name
    namespace = kubernetes_namespace.nginx_ingress.metadata[0].name
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

resource "kubernetes_secret" "waf_policy_bundle" {
  metadata {
    name      = local.bundle_secret_name
    namespace = kubernetes_namespace.nginx_ingress.metadata[0].name
  }

  type = "Opaque"

  binary_data = {
    (local.policy_bundle_filename) = filebase64(var.compiled_policy_path)
  }
}
