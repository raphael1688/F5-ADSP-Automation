resource "volterra_sensitive_data_policy" "this" {
  depends_on = [volterra_namespace.this]

  count     = var.xc_sensitive_data_policy ? 1 : 0
  name      = format("%s-sdp-%s", local.project_prefix, local.build_suffix)
  namespace = var.xc_namespace

  compliances = var.xc_sensitive_data_compliances
}
