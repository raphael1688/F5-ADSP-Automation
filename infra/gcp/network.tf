############################ VPC ############################

# Create VPC network
resource "google_compute_network" "vpc" {
  name                    = "${var.project_prefix}-vpc-${random_id.build_suffix.hex}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "VPC for ${var.project_prefix}"
}

############################ CIDR PLAN ############################
# This deployment is single-region and does not require multiple AZs.
# We carve the VPC CIDR into 4 non-overlapping regional subnet ranges:
# - external (/18)
# - internal (/18)
# - app     (/18)
# - management (small /24 carved out of its own /18 block)

locals {
  # Split the VPC CIDR into 4 equal /18 blocks (assuming /16 base; still works for other sizes)
  cidr_block_mgmt_super = cidrsubnet(var.cidr, 2, 0)
  cidr_block_external   = cidrsubnet(var.cidr, 2, 1)
  cidr_block_internal   = cidrsubnet(var.cidr, 2, 2)
  cidr_block_app        = cidrsubnet(var.cidr, 2, 3)

  # Management is intentionally smaller: first /24 within the mgmt supernet
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

############################ Default route to Internet ############################

resource "google_compute_route" "default_internet" {
  name             = "${var.project_prefix}-default-internet"
  network          = google_compute_network.vpc.id
  dest_range       = "0.0.0.0/0"
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000
}

############################ NAT (optional) ############################

resource "google_compute_router" "nat_router" {
  count   = var.create_nat_gateway ? 1 : 0
  name    = "${var.project_prefix}-router"
  region  = var.gcp_region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  count                              = var.create_nat_gateway ? 1 : 0
  name                               = "${var.project_prefix}-nat"
  router                             = google_compute_router.nat_router[0].name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
