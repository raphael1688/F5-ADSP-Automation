resource "helm_release" "nginx_ingress" {
  name      = local.release_name
  namespace = kubernetes_namespace.nginx_ingress.metadata[0].name
  chart     = var.chart_path

  values = [local.chart_values]

  timeout = 600

  depends_on = [
    kubernetes_secret.nginx_license,
    kubernetes_secret.registry,
    kubectl_manifest.nic_crds,
  ]
}

resource "kubectl_manifest" "waf_policy" {
  yaml_body = yamlencode({
    apiVersion = "k8s.nginx.org/v1"
    kind       = "Policy"
    metadata = {
      name      = var.waf_policy_name
      namespace = kubernetes_namespace.nginx_ingress.metadata[0].name
    }
    spec = {
      waf = {
        enable   = true
        apBundle = local.policy_bundle_filename
      }
    }
  })

  depends_on = [helm_release.nginx_ingress]
}
