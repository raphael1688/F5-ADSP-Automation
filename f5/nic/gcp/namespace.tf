resource "kubernetes_namespace" "nginx_ingress" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      owner                          = local.resource_owner
    }
  }
}
