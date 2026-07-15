# Satisfies the XC origin contract: f5/xc reads k8s_ingress_external_ip from the
# backend_k8s_ingress remote state.
output "k8s_ingress_external_ip" {
  value       = try(data.kubernetes_service_v1.dataplane.status[0].load_balancer[0].ingress[0].ip, null)
  description = "External IP of the NGF data plane LoadBalancer. Used as the XC origin."
}

output "ngf_namespace" {
  value       = kubernetes_namespace.nginx_gateway.metadata[0].name
  description = "Namespace hosting the NGF control plane and the Gateway."
}

output "gateway_name" {
  value       = local.gateway_name
  description = "Name of the Gateway. Apps reference it from their HTTPRoute parentRefs."
}

output "gateway_namespace" {
  value       = kubernetes_namespace.nginx_gateway.metadata[0].name
  description = "Namespace of the Gateway. Apps reference it cross-namespace from their HTTPRoute."
}

output "gatewayclass_name" {
  value       = var.gatewayclass_name
  description = "GatewayClass backing the Gateway."
}
