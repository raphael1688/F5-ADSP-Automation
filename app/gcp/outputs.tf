output "app_host" {
  value       = var.app_host
  description = "FQDN exposed by the NIC VirtualServer. Used as the XC origin host in the planned XC block."
}

output "app_namespace" {
  value       = kubernetes_namespace.app.metadata[0].name
  description = "Namespace the workload runs in."
}

output "release_name" {
  value       = helm_release.comfy_capybara.name
  description = "Helm release name."
}

output "virtualserver_name" {
  value       = local.release_name
  description = "Name of the VirtualServer resource managed by this module."
}

output "nic_external_ip" {
  value       = local.nic.nic_external_ip
  description = "Passthrough from NIC remote state. The XC block will use this as origin_server."
}
