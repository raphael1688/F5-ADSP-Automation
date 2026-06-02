locals {
  infra = data.terraform_remote_state.infra.outputs
  k8s   = data.terraform_remote_state.k8s.outputs
  nic   = data.terraform_remote_state.nic.outputs

  project_prefix = local.infra.project_prefix
  resource_owner = local.infra.resource_owner
  build_suffix   = local.infra.build_suffix

  cluster_host           = local.k8s.kubernetes_api_server_url
  cluster_ca_certificate = local.k8s.cluster_ca_certificate

  release_name = var.release_name != "" ? var.release_name : format("%s-comfy-%s", local.project_prefix, local.build_suffix)

  waf_policy_ref = {
    name      = local.nic.waf_policy_name
    namespace = local.nic.waf_policy_namespace
  }

  server_wide_policies = var.attach_waf_server_wide ? [local.waf_policy_ref] : []
  api_route_policies   = var.attach_waf_to_api_route ? [local.waf_policy_ref] : []

  image_block = merge(
    { pullPolicy = "IfNotPresent" },
    var.image_registry != "" ? { registry = var.image_registry } : {},
    var.image_tag != "" ? { tag = var.image_tag } : {},
  )

  # The chart no longer emits a VirtualServer; ingress is the consumer's concern,
  # produced by virtualserver.tf in this module.
  chart_values = {
    image            = local.image_block
    imagePullSecrets = var.image_pull_secret_name != "" ? [{ name = var.image_pull_secret_name }] : []
  }

  # Service names emitted by the chart: <release>-api and <release>-frontend.
  api_service_name      = "${local.release_name}-api"
  frontend_service_name = "${local.release_name}-frontend"
  api_service_port      = 8000
  frontend_service_port = 8080
}
