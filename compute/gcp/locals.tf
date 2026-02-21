locals {
  infra = data.terraform_remote_state.infra.outputs

  project_prefix = local.infra.project_prefix
  resource_owner = local.infra.resource_owner
  build_suffix   = local.infra.build_suffix
  gcp_region     = local.infra.gcp_region

  # Network wiring from infra outputs
  network_id    = data.terraform_remote_state.infra.outputs.vpc_network_id
  # Prefer app subnet; fall back to internal then external then mgmt
  subnetwork_id = try(
    data.terraform_remote_state.infra.outputs.app_subnet_id,
    data.terraform_remote_state.infra.outputs.int_subnet_id,
    data.terraform_remote_state.infra.outputs.ext_subnet_id,
    data.terraform_remote_state.infra.outputs.mgmt_subnet_id
  )

  # Firewall tag to attach to this instance (internal by default)
  instance_network_tags = distinct(compact([
    try(data.terraform_remote_state.infra.outputs.tag_int, ""),
    var.additional_network_tag
  ]))

  # SSH keys: always include generated key; append external key if provided
  ssh_keys_metadata = join("\n", compact([
    "adminuser:${tls_private_key.vm_ssh_key.public_key_openssh}",
    var.ssh_pub != "" ? "adminuser:${var.ssh_pub}" : "",
  ]))

  juice_shop = {
    service_name = "juice-shop"
    image = "bkimminich/juice-shop:latest"
  }

  crapi = {
    service_name = "crapi"
    image = ""
  }

}
