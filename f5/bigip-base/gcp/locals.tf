locals {
  infra = data.terraform_remote_state.infra.outputs
  bigip_config = data.terraform_remote_state.bigip_config.outputs
  as3_gcs_uri  = local.bigip_config.as3_gcs_uri

  project_prefix = local.infra.project_prefix
  resource_owner = local.infra.resource_owner
  build_suffix   = local.infra.build_suffix

  # Single-NIC: only need external subnet (for management + data plane)
  ext_subnet_id = local.infra.ext_subnet_id

  vm_name = var.vm_name == "" ? format("%s-bigip1-%s", local.project_prefix, local.build_suffix) : var.vm_name

  # Parse version from GitHub release URL (index 7 = version tag e.g. "v1.34.0")
  DO_VER   = var.DO_VER != "" ? var.DO_VER : split("/", var.DO_URL)[7]
  AS3_VER  = var.AS3_VER != "" ? var.AS3_VER : split("/", var.AS3_URL)[7]
  TS_VER   = var.TS_VER != "" ? var.TS_VER : split("/", var.TS_URL)[7]
  CFE_VER  = var.CFE_VER != "" ? var.CFE_VER : var.CFE_URL != "" ? split("/", var.CFE_URL)[7] : ""
  FAST_VER = var.FAST_VER != "" ? var.FAST_VER : split("/", var.FAST_URL)[7]

  # If Secret Manager is disabled, use generated password. If enabled, the template expects secretId.
  bigip_password_value = var.gcp_secret_manager_authentication ? var.gcp_secret_id : random_password.bigip_admin.result

  startup_script = templatefile("${path.module}/templates/f5_onboard.tmpl", {
    bigip_username                    = var.f5_username
    ssh_keypair                       = chomp(file(var.f5_ssh_publickey))
    gcp_secret_manager_authentication = var.gcp_secret_manager_authentication
    bigip_password                    = local.bigip_password_value

    INIT_URL = var.INIT_URL

    DO_URL   = var.DO_URL
    DO_VER   = local.DO_VER
    AS3_URL  = var.AS3_URL
    AS3_VER  = local.AS3_VER
    TS_URL   = var.TS_URL
    TS_VER   = local.TS_VER
    CFE_URL  = var.CFE_URL
    CFE_VER  = local.CFE_VER
    FAST_URL = var.FAST_URL
    FAST_VER = local.FAST_VER

    # Single-NIC: disable NIC swap logic (template checks if NIC_COUNT == "true")
    NIC_COUNT = "false"

    # AS3 GCS configuration pull
    # URI is derived from bucket+path (matches bigip-config formula).
    AS3_GCS_URI = local.as3_gcs_uri

    asm = var.asm
    apm = var.apm
  })
}
