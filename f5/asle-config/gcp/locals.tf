locals {
  bigip_ip       = try(data.terraform_remote_state.bigip_base[0].outputs.bigip_mgmt_internal_ip, "")
  bigip_password = try(data.terraform_remote_state.bigip_base[0].outputs.bigip_admin_password, "")

  bundle_gcs_uri = "gs://${var.tf_state_bucket}/${var.bundle_gcs_path}"

  bundle = {
    operations = [
      {
        method = "POST"
        path   = "/api/bigip"
        payload = {
          name     = var.bigip_onboard_name
          ip       = local.bigip_ip
          port     = var.bigip_onboard_port
          user     = var.bigip_onboard_user
          password = local.bigip_password
        }
      },
    ]
  }
}
