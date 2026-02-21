#Global
output "project_prefix" {
  value = var.project_prefix
}
output "resource_owner" {
  value = var.resource_owner
}
output "build_suffix" {
  value = random_id.build_suffix.hex
}

#Outputs
output "gcp_project_id" {
  value = var.gcp_project_id
}
output "gcp_region" {
  value = var.gcp_region
}

output "vpc_network_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "vpc_network_id" {
  description = "VPC network ID"
  value       = google_compute_network.vpc.id
}

# Subnet CIDRs (single-region; no multi-AZ)
output "mgmt_cidr" {
  description = "Management subnet CIDR"
  value       = google_compute_subnetwork.management.ip_cidr_range
}
output "ext_cidr" {
  description = "External subnet CIDR"
  value       = google_compute_subnetwork.external.ip_cidr_range
}
output "int_cidr" {
  description = "Internal subnet CIDR"
  value       = google_compute_subnetwork.internal.ip_cidr_range
}
output "app_cidr" {
  description = "App subnet CIDR"
  value       = google_compute_subnetwork.app.ip_cidr_range
}

# Subnet IDs
output "mgmt_subnet_id" {
  value       = google_compute_subnetwork.management.id
  description = "Management subnet ID"
}
output "ext_subnet_id" {
  value       = google_compute_subnetwork.external.id
  description = "External subnet ID"
}
output "int_subnet_id" {
  value       = google_compute_subnetwork.internal.id
  description = "Internal subnet ID"
}
output "app_subnet_id" {
  value       = google_compute_subnetwork.app.id
  description = "App subnet ID"
}

# Firewall network tags (used by compute)
output "tag_ext" {
  value       = "${var.project_prefix}-ext"
  description = "Network tag for external-facing instances"
}
output "tag_mgmt" {
  value       = "${var.project_prefix}-mgmt"
  description = "Network tag for management-facing instances"
}
output "tag_int" {
  value       = "${var.project_prefix}-int"
  description = "Network tag for internal instances"
}
