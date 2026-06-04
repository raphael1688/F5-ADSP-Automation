locals {
  infra = data.terraform_remote_state.infra.outputs
  k8s   = data.terraform_remote_state.k8s.outputs

  project_prefix = local.infra.project_prefix
  resource_owner = local.infra.resource_owner
  build_suffix   = local.infra.build_suffix

  cluster_host           = local.k8s.kubernetes_api_server_url
  cluster_ca_certificate = local.k8s.cluster_ca_certificate

  release_name = format("%s-nic-%s", local.project_prefix, local.build_suffix)
  ksa_name     = "nic-nap-bundle-reader"

  policy_bundle_filename = "compiled_policy.tgz"
  license_secret_name    = "license-token"
  regcred_secret_name    = "regcred"

  chart_values = templatefile("${path.module}/values.yaml.tftpl", {
    license_secret_name  = local.license_secret_name
    regcred_secret_name  = local.regcred_secret_name
    ksa_name             = local.ksa_name
    gsa_email            = var.gcp_runtime_service_account_email
    nap_bundle_bucket    = var.tf_state_bucket
    nap_bundle_subdir    = var.nap_bundle_subdir
    nic_image_repository = var.nic_image_repository
    nic_image_tag        = var.nic_image_tag
    nap_enforcer_image   = var.nap_enforcer_image
    nap_enforcer_tag     = var.nap_enforcer_tag
    nap_config_mgr_image = var.nap_config_mgr_image
    nap_config_mgr_tag   = var.nap_config_mgr_tag
  })
}
