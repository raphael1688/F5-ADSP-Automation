# waf.tf

resource "volterra_app_firewall" "waap-tf" {
  depends_on = [volterra_namespace.this]

  name        = format("%s-xcw-%s", local.project_prefix, local.build_suffix)
  description = format("WAF for %s", "${local.project_prefix}-xcw-${local.build_suffix}")
  namespace   = var.xc_namespace

  allow_all_response_codes   = true
  default_anonymization      = true
  use_default_blocking_page  = true
  default_bot_setting        = true
  default_detection_settings = true
  use_loadbalancer_setting   = true

  blocking = var.xc_waf_blocking
}
