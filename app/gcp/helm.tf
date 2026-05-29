resource "helm_release" "comfy_capybara" {
  name       = local.release_name
  namespace  = kubernetes_namespace.app.metadata[0].name
  repository = var.chart_repository
  chart      = var.chart_name
  version    = var.chart_version

  values = [yamlencode(local.chart_values)]

  timeout = 600

  depends_on = [kubernetes_namespace.app]
}
