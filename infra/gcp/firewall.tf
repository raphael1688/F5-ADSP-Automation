############################ Firewall Rules (SG Equivalents) ############################

# In GCP, firewall rules are attached to the VPC and target instances via network tags.
# Apply these tags to VMs / instance templates / MIGs / GKE nodes as appropriate.
locals {
  tag_external   = "${var.project_prefix}-ext"
  tag_management = "${var.project_prefix}-mgmt"
  tag_internal   = "${var.project_prefix}-int"
}

# Management from admin_src_addr
resource "google_compute_firewall" "mgmt_ingress_admin" {
  name      = "${var.project_prefix}-fw-mgmt-admin-${random_id.build_suffix.hex}"
  network   = google_compute_network.vpc.name
  direction = "INGRESS"
  priority  = 1000

  target_tags   = [local.tag_management]
  source_ranges = var.admin_src_addr

  allow {
    protocol = "tcp"
    # 22=SSH, 80=HTTP, 443=HTTPS, 8000/8080=app ports, 8025=Mailhog, 8443=mgmt, 8888=crAPI
    ports = ["22", "80", "443", "8000", "8025", "8080", "8443", "8888"]
  }
}

resource "google_compute_firewall" "mgmt_egress_all" {
  name      = "${var.project_prefix}-fw-mgmt-egress-${random_id.build_suffix.hex}"
  network   = google_compute_network.vpc.name
  direction = "EGRESS"
  priority  = 1000

  target_tags        = [local.tag_management]
  destination_ranges = ["0.0.0.0/0"]

  allow { protocol = "all" }
}

# Internal: allow all from VPC CIDR
resource "google_compute_firewall" "internal_ingress_vpc_all" {
  name      = "${var.project_prefix}-fw-int-vpc-all-${random_id.build_suffix.hex}"
  network   = google_compute_network.vpc.name
  direction = "INGRESS"
  priority  = 1000

  target_tags   = [local.tag_internal]
  source_ranges = [var.cidr]

  allow { protocol = "all" }
}

resource "google_compute_firewall" "internal_egress_all" {
  name      = "${var.project_prefix}-fw-int-egress-${random_id.build_suffix.hex}"
  network   = google_compute_network.vpc.name
  direction = "EGRESS"
  priority  = 1000

  target_tags        = [local.tag_internal]
  destination_ranges = ["0.0.0.0/0"]

  allow { protocol = "all" }
}

############################ BIG-IP Firewall Rules (Conditional) ############################

# BIG-IP Management Access
resource "google_compute_firewall" "bigip_mgmt" {
  count     = var.bigip ? 1 : 0
  name      = "${var.project_prefix}-fw-bigip-mgmt-${random_id.build_suffix.hex}"
  network   = google_compute_network.vpc.name
  direction = "INGRESS"
  priority  = 1000

  target_tags   = ["${var.project_prefix}-bigip-mgmt"]
  source_ranges = var.admin_src_addr

  allow {
    protocol = "tcp"
    ports    = ["22", "443", "8443"] # SSH, HTTPS, Config Utility
  }
}

# BIG-IP External (Data Plane)
resource "google_compute_firewall" "bigip_external" {
  count     = var.bigip ? 1 : 0
  name      = "${var.project_prefix}-fw-bigip-ext-${random_id.build_suffix.hex}"
  network   = google_compute_network.vpc.name
  direction = "INGRESS"
  priority  = 1000

  target_tags = ["${var.project_prefix}-bigip-ext"]
  source_ranges = concat(var.admin_src_addr, [
    "5.182.215.0/25",
    "84.54.61.0/25",
    "23.158.32.0/25",
    "84.54.62.0/25",
    "185.94.142.0/25",
    "185.94.143.0/25",
    "159.60.190.0/24",
    "159.60.168.0/24",
    "159.60.180.0/24",
    "159.60.174.0/24",
    "159.60.176.0/24",
    "50.53.127.175/32",
    "104.219.107.84/32",
  ])

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

