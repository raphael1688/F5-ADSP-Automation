resource "kubernetes_namespace" "nginx_gateway" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      owner                          = local.resource_owner
    }
  }
}
