locals {
  infra = data.terraform_remote_state.infra.outputs

  project_prefix = local.infra.project_prefix
  resource_owner = local.infra.resource_owner
  build_suffix   = local.infra.build_suffix

  subnetwork_id = try(
    local.infra.app_subnet_id,
    local.infra.int_subnet_id,
    local.infra.ext_subnet_id,
    local.infra.mgmt_subnet_id
  )

  instance_network_tags = distinct(compact([
    try(local.infra.tag_int, ""),
    var.additional_network_tag
  ]))

  ssh_keys_metadata = join("\n", compact([
    "adminuser:${tls_private_key.vm_ssh_key.public_key_openssh}",
    var.ssh_pub != "" ? "adminuser:${var.ssh_pub}" : "",
  ]))

  service_name = "asle"
}
