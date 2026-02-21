resource "random_password" "bigip_admin" {
  length      = 16
  special     = false
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
}

# Reserve single internal IP for 1-NIC deployment on external subnet
# (management + data plane + backend communication all on one interface)
resource "google_compute_address" "primary_ip" {
  name         = format("%s-bigip-primary-ip-%s", local.project_prefix, local.build_suffix)
  region       = var.gcp_region
  address_type = "INTERNAL"
  subnetwork   = local.ext_subnet_id
}

module "bigip" {
  source  = "F5Networks/bigip-module/gcp"
  version = "1.1.22"

  prefix     = local.project_prefix
  vm_name    = local.vm_name
  project_id = var.gcp_project_id
  zone       = var.gcp_zone
  image      = var.image_name

  service_account = var.gcp_runtime_service_account_email

  sleep_time       = "300s"
  machine_type     = var.machine_type
  disk_type        = var.disk_type
  disk_size_gb     = var.disk_size_gb
  min_cpu_platform = var.min_cpu_platform

  # Use official startup script rendered by templatefile()
  custom_user_data = local.startup_script

  # Single-NIC: use mgmt_subnet_ids for the primary (and only) interface
  # Attached to external subnet with public IP for management + data plane
  mgmt_subnet_ids = [{
    subnet_id          = local.ext_subnet_id
    public_ip          = true
    private_ip_primary = google_compute_address.primary_ip.address
  }]

  f5_username      = var.f5_username
  f5_ssh_publickey = var.f5_ssh_publickey

  network_tags = [
    format("%s-bigip-ext", local.project_prefix),
    format("%s-bigip-mgmt", local.project_prefix),
  ]

  labels = {
    name  = local.vm_name
    owner = local.resource_owner
  }
}
