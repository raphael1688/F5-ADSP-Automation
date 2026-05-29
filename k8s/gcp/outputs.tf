output "cluster_name" {
  value       = google_container_cluster.primary.name
  description = "GKE cluster name."
}

output "cluster_location" {
  value       = google_container_cluster.primary.location
  description = "GKE cluster zone."
}

output "cluster_endpoint" {
  value       = google_container_cluster.primary.endpoint
  description = "GKE control plane endpoint (IP)."
}

output "cluster_ca_certificate" {
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  description = "Base64-encoded cluster CA certificate."
}

output "cluster_access_token" {
  value       = nonsensitive(data.google_client_config.current.access_token)
  description = "Short-lived GCP access token usable by the kubernetes/helm providers downstream."
}

output "kubernetes_api_server_url" {
  value       = "https://${google_container_cluster.primary.endpoint}"
  description = "HTTPS URL for the GKE API server."
}
