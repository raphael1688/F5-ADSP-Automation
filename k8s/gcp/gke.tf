resource "google_container_cluster" "primary" {
  name     = local.cluster_name
  location = var.gcp_zone

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false

  node_config {
    service_account = var.node_service_account != "" ? var.node_service_account : null
  }

  network    = local.network_name
  subnetwork = local.k8s_subnet_name

  release_channel {
    channel = var.release_channel
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = local.k8s_pods_range_name
    services_secondary_range_name = local.k8s_services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(local.master_authorized_cidrs) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = local.master_authorized_cidrs
        content {
          cidr_block = cidr_blocks.value
        }
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  datapath_provider = "ADVANCED_DATAPATH"

  resource_labels = {
    owner = local.resource_owner
  }
}

resource "google_container_node_pool" "primary" {
  name       = "${local.cluster_name}-pool"
  cluster    = google_container_cluster.primary.name
  location   = google_container_cluster.primary.location
  node_count = var.node_count

  node_config {
    machine_type = var.node_machine_type
    disk_size_gb = var.node_disk_size_gb
    disk_type    = var.node_disk_type

    service_account = var.node_service_account != "" ? var.node_service_account : null

    tags = [local.tag_nic_ext]

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      owner = local.resource_owner
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
