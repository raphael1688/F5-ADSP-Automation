############################ VPC ############################

# Create VPC network
resource "google_compute_network" "vpc" {
  name                    = "${var.project_prefix}-vpc-${random_id.build_suffix.hex}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "VPC for ${var.project_prefix}"
}

############################ CIDR PLAN ############################
# Single-region VPC carved into four /18 supernets: mgmt, external,
# internal, app. Management uses only the first /24 of its supernet;
# the rest of that /18 is reserved for future mgmt-adjacent subnets.

locals {
  cidr_block_mgmt_super = cidrsubnet(var.cidr, 2, 0)
  cidr_block_external   = cidrsubnet(var.cidr, 2, 1)
  cidr_block_internal   = cidrsubnet(var.cidr, 2, 2)
  cidr_block_app        = cidrsubnet(var.cidr, 2, 3)

  cidr_management = cidrsubnet(local.cidr_block_mgmt_super, 6, 0)
}

############################ Subnets ############################

resource "google_compute_subnetwork" "management" {
  name          = "${var.project_prefix}-mgmt-subnet"
  ip_cidr_range = local.cidr_management
  region        = var.gcp_region
  network       = google_compute_network.vpc.id
}

resource "google_compute_subnetwork" "external" {
  name          = "${var.project_prefix}-ext-subnet"
  ip_cidr_range = local.cidr_block_external
  region        = var.gcp_region
  network       = google_compute_network.vpc.id
}

resource "google_compute_subnetwork" "internal" {
  name          = "${var.project_prefix}-int-subnet"
  ip_cidr_range = local.cidr_block_internal
  region        = var.gcp_region
  network       = google_compute_network.vpc.id
}

resource "google_compute_subnetwork" "app" {
  name          = "${var.project_prefix}-app-subnet"
  ip_cidr_range = local.cidr_block_app
  region        = var.gcp_region
  network       = google_compute_network.vpc.id
}

############################ GKE Subnet ############################

locals {
  k8s_pods_range_name     = "${var.project_prefix}-k8s-pods"
  k8s_services_range_name = "${var.project_prefix}-k8s-svcs"
}

resource "google_compute_subnetwork" "k8s" {
  count                    = var.gke ? 1 : 0
  name                     = "${var.project_prefix}-k8s-subnet"
  ip_cidr_range            = var.k8s_cidr
  region                   = var.gcp_region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = local.k8s_pods_range_name
    ip_cidr_range = var.k8s_pods_cidr
  }

  secondary_ip_range {
    range_name    = local.k8s_services_range_name
    ip_cidr_range = var.k8s_services_cidr
  }
}

############################ Default route to Internet ############################

resource "google_compute_route" "default_internet" {
  name             = "${var.project_prefix}-default-internet"
  network          = google_compute_network.vpc.id
  dest_range       = "0.0.0.0/0"
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000
}

############################ NAT ############################

locals {
  nat_enabled = var.create_nat_gateway || var.gke
}

resource "google_compute_router" "nat_router" {
  count   = local.nat_enabled ? 1 : 0
  name    = "${var.project_prefix}-router"
  region  = var.gcp_region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  count                              = local.nat_enabled ? 1 : 0
  name                               = "${var.project_prefix}-nat"
  router                             = google_compute_router.nat_router[0].name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
