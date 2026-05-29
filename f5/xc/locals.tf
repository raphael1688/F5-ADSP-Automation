# locals.tf 

locals {
  # Shared values from infra remote state
  project_prefix = data.terraform_remote_state.infra.outputs.project_prefix
  build_suffix   = data.terraform_remote_state.infra.outputs.build_suffix
  gcp_region     = data.terraform_remote_state.infra.outputs.gcp_region

  # Origin backend auto-discovery (fallback to var.origin_server if not using remote state)
  origin_bigip = var.backend_bigip ? try(data.terraform_remote_state.bigip[0].outputs.bigip_external_public_ip, "") : ""
  origin_nic   = var.backend_nic ? try(data.terraform_remote_state.nic[0].outputs.nic_external_ip, "") : ""
  # origin_compute = var.backend_compute ? try(data.terraform_remote_state.compute[0].outputs.docker_host_external_ip, "") : ""

  # Priority: BIG-IP VIP > NIC LB IP > manual origin_server
  origin_server = coalesce(
    local.origin_bigip,
    local.origin_nic,
    # local.origin_compute,
    var.origin_server
  )

  origin_port = var.origin_port

  # DNS-based pool if origin is a hostname (not IP)
  dns_origin_pool = can(regex("^[a-zA-Z]", local.origin_server))
}
