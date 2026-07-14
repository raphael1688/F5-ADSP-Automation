output "juice_shop_internal_ip" {
  value = try(google_compute_instance.docker_host["juice-shop"].network_interface[0].network_ip, "")
}

output "crapi_internal_ip" {
  value = try(google_compute_instance.docker_host["crapi"].network_interface[0].network_ip, "")
}

output "comfy_capybara_internal_ip" {
  value = try(google_compute_instance.docker_host["comfy-capybara"].network_interface[0].network_ip, "")
}

output "private_key" {
  value     = tls_private_key.vm_ssh_key.private_key_pem
  sensitive = true
}
