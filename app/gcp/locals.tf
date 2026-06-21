locals {
  infra       = data.terraform_remote_state.infra.outputs
  k8s         = data.terraform_remote_state.k8s.outputs
  k8s_ingress = data.terraform_remote_state.k8s_ingress.outputs

  project_prefix = local.infra.project_prefix
  resource_owner = local.infra.resource_owner
  build_suffix   = local.infra.build_suffix

  cluster_host           = local.k8s.kubernetes_api_server_url
  cluster_ca_certificate = local.k8s.cluster_ca_certificate

  release_name = var.release_name != "" ? var.release_name : format("%s-comfy-%s", local.project_prefix, local.build_suffix)

  # waf_policy_* exist only in NIC state; absent when the backend is NGF.
  waf_policy_ref = {
    name      = try(local.k8s_ingress.waf_policy_name, "")
    namespace = try(local.k8s_ingress.waf_policy_namespace, "")
  }

  server_wide_policies = var.attach_waf_server_wide ? [local.waf_policy_ref] : []
  api_route_policies   = var.attach_waf_to_api_route ? [local.waf_policy_ref] : []

  # gateway_* exist only in NGF state; consumed by the HTTPRoute parentRef.
  gateway_name      = try(local.k8s_ingress.gateway_name, "")
  gateway_namespace = try(local.k8s_ingress.gateway_namespace, "")

  image_block = merge(
    { pullPolicy = "IfNotPresent" },
    var.image_registry != "" ? { registry = var.image_registry } : {},
    var.image_tag != "" ? { tag = var.image_tag } : {},
  )

  chart_values = {
    image            = local.image_block
    imagePullSecrets = var.image_pull_secret_name != "" ? [{ name = var.image_pull_secret_name }] : []
    fullnameOverride = local.release_name
  }

  api_service_name      = "${local.release_name}-api"
  frontend_service_name = "${local.release_name}-frontend"
  api_service_port      = 8000
  frontend_service_port = 8080
}
