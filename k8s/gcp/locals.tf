locals {
  infra = data.terraform_remote_state.infra.outputs

  project_prefix = local.infra.project_prefix
  resource_owner = local.infra.resource_owner
  build_suffix   = local.infra.build_suffix

  network_name            = local.infra.vpc_network_name
  k8s_subnet_name         = local.infra.k8s_subnet_name
  k8s_pods_range_name     = local.infra.k8s_pods_range_name
  k8s_services_range_name = local.infra.k8s_services_range_name
  tag_nic_ext             = local.infra.tag_nic_ext

  cluster_name = "${local.project_prefix}-gke-${local.build_suffix}"

  master_authorized_cidrs = toset(concat(var.admin_src_addr, var.master_authorized_networks_extra))
}
