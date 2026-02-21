output "bigip_admin_password" {
  value       = random_password.bigip_admin.result
  sensitive   = true
  description = "Generated BIG-IP admin password (used when Secret Manager auth is disabled)."
}

output "bigip_name" {
  value       = local.vm_name
  description = "BIG-IP instance name"
}

# Single-NIC: management interface is the primary (and only) interface
output "bigip_mgmt_internal_ip" {
  value       = google_compute_address.primary_ip.address
  description = "BIG-IP management internal IP (single-NIC: also handles data plane)"
}

# Public IP for management access and external traffic
output "bigip_public_ip" {
  value       = module.bigip.mgmtPublicIP
  description = "BIG-IP public IP (for management GUI/SSH and data plane)"
}

# Alias for XC integration (references same public IP)
output "bigip_external_public_ip" {
  value       = module.bigip.mgmtPublicIP
  description = "BIG-IP external public IP (alias for bigip_public_ip, used by XC module)"
}

# Pass-through for visibility (module output names are module-defined)
output "bigip_module" {
  value     = module.bigip
  sensitive = true
}

output "as3_uri" {
  value = local.as3_gcs_uri
  description = "Testing"
}