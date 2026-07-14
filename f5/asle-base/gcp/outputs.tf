output "asle_internal_ip" {
  value       = google_compute_instance.asle.network_interface[0].network_ip
  description = "ASLE instance internal IP"
}

output "asle_name" {
  value       = google_compute_instance.asle.name
  description = "ASLE instance name"
}

output "private_key" {
  value       = tls_private_key.vm_ssh_key.private_key_pem
  sensitive   = true
  description = "Generated SSH private key for the ASLE instance"
}
