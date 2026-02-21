locals {
  juice_shop_names = [for instance in google_compute_instance.juice_shop : instance.name]
  js_name_formatted = local.juice_shop_names == [] ? "not set" : join(", ", [for value in local.juice_shop_names : value])
  crapi_names = [for instance in google_compute_instance.crapi : instance.name]
  crapi_name_formatted = local.crapi_names == [] ? "not set" : join(", ", [for value in local.crapi_names : value])
}

output "instance_name_js" {
  value = "juice shop names: ${local.js_name_formatted}"
}

output "instance_name_cr" {
  value = "crapi names: ${local.crapi_name_formatted}"
}

output "juice_shop_internal_ip" {
  value = length(google_compute_instance.juice_shop) > 0 ? google_compute_instance.juice_shop[0].network_interface[0].network_ip : ""
}

output "crapi_internal_ip" {
  value = length(google_compute_instance.crapi) > 0 ? google_compute_instance.crapi[0].network_interface[0].network_ip : ""
}

output "private_key" {
  value     = tls_private_key.vm_ssh_key.private_key_pem
  sensitive = true
}
