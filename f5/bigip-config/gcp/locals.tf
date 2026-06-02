locals {
  infra          = data.terraform_remote_state.infra.outputs
  project_prefix = local.infra.project_prefix
  resource_owner = local.infra.resource_owner

  app_server_ip = var.backend_compute ? coalesce(
    try(data.terraform_remote_state.compute[0].outputs.juice_shop_internal_ip, ""),
    try(data.terraform_remote_state.compute[0].outputs.crapi_internal_ip, ""),
    try(data.terraform_remote_state.compute[0].outputs.comfy_capybara_internal_ip, ""),
    var.app_server_ip
  ) : var.app_server_ip

  asle_ip = var.backend_compute ? try(
    data.terraform_remote_state.compute[0].outputs.asle_internal_ip, ""
  ) : ""

  bigip_internal_ip = var.backend_bigip_base ? try(
    data.terraform_remote_state.bigip_base[0].outputs.bigip_mgmt_internal_ip, ""
  ) : ""

  as3_gcs_bucket = var.tf_state_bucket
  as3_gcs_uri    = "gs://${local.as3_gcs_bucket}/${var.as3_gcs_path}"

  asle_log_irule = <<-IRULE
    when CLIENT_ACCEPTED {
      set hsl [HSL::open -proto TCP -pool internal_logging_pool]
    }
    when HTTP_REQUEST {
      set path [HTTP::path]
      if { $path starts_with "/docs" || $path starts_with "/openapi.json" || $path starts_with "/redoc" } {
        pool api_pool
      }
      HSL::send $hsl "{ \"event\": \"request\", \"client\": \"[IP::client_addr]\", \"method\": \"[HTTP::method]\", \"uri\": \"[HTTP::uri]\" }\n"
    }
    when HTTP_RESPONSE {
      HSL::send $hsl "{ \"event\": \"response\", \"client\": \"[IP::client_addr]\", \"status\": [HTTP::status] }\n"
    }
  IRULE

  as3_declaration = templatefile(var.awaf_config_payload, {
    app_server_ip       = local.app_server_ip
    app_server_port     = var.app_server_port
    api_server_port     = var.api_server_port
    asle_ip             = local.asle_ip
    asle_telemetry_port = var.asle_telemetry_port
    bigip_internal_ip   = local.bigip_internal_ip
    cert_pem_b64        = base64encode(tls_self_signed_cert.front_door.cert_pem)
    key_pem_b64         = base64encode(tls_private_key.front_door.private_key_pem)
    irule_b64           = base64encode(local.asle_log_irule)
  })
}
