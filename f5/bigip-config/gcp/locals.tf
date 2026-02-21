locals {
  #GLOBAL
  infra          = data.terraform_remote_state.infra.outputs
  project_prefix = local.infra.project_prefix
  resource_owner = local.infra.resource_owner

  #App Server - try juice_shop, then crapi from compute state, then manual variable
  app_server_ip = var.backend_compute ? coalesce(
    try(data.terraform_remote_state.compute[0].outputs.juice_shop_internal_ip, ""),
    try(data.terraform_remote_state.compute[0].outputs.crapi_internal_ip, ""),
    var.app_server_ip
  ) : var.app_server_ip

  #AS3 GCS Configuration
  as3_gcs_bucket = var.tf_state_bucket
  as3_gcs_uri    = "gs://${local.as3_gcs_bucket}/${var.as3_gcs_path}"

  # Rendered AS3 declaration
  as3_declaration = templatefile(var.awaf_config_payload, {
    app_server_ip = local.app_server_ip
  })
}
