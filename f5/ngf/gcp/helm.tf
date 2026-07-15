resource "helm_release" "ngf" {
  name       = local.release_name
  namespace  = kubernetes_namespace.nginx_gateway.metadata[0].name
  repository = "oci://ghcr.io/nginx/charts"
  chart      = "nginx-gateway-fabric"
  version    = var.chart_version

  values = [local.chart_values]

  timeout = 600

  depends_on = [
    kubernetes_secret.nginx_license,
    kubernetes_secret.registry,
    kubectl_manifest.gateway_api_crds,
  ]
}
