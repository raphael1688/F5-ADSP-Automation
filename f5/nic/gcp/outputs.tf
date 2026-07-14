# The LoadBalancer Service and its external IP are provisioned asynchronously
# after the Helm release installs. Give GCP time to assign it.
resource "time_sleep" "wait_dataplane" {
  depends_on      = [helm_release.nginx_ingress]
  create_duration = "180s"
}

data "kubernetes_service_v1" "nic" {
  metadata {
    name      = "${helm_release.nginx_ingress.name}-nginx-ingress-controller"
    namespace = helm_release.nginx_ingress.namespace
  }

  depends_on = [time_sleep.wait_dataplane]
}

output "nic_namespace" {
  value       = kubernetes_namespace.nginx_ingress.metadata[0].name
  description = "Namespace hosting the NIC release and the WAF policy."
}

output "nic_service_name" {
  value       = try(data.kubernetes_service_v1.nic.metadata[0].name, null)
  description = "Kubernetes Service name for the NIC LoadBalancer."
}

output "k8s_ingress_external_ip" {
  value       = try(data.kubernetes_service_v1.nic.status[0].load_balancer[0].ingress[0].ip, null)
  description = "External IP assigned to the NIC LoadBalancer Service. Used as the XC origin."
}

output "waf_policy_name" {
  value       = var.waf_policy_name
  description = "Name of the NIC Policy resource exposing the compiled NAP bundle."
}

output "waf_policy_namespace" {
  value       = kubernetes_namespace.nginx_ingress.metadata[0].name
  description = "Namespace of the WAF Policy resource. Apps reference it cross-namespace from their VirtualServer."
}
