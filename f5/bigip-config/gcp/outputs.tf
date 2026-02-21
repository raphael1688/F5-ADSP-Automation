# Outputs consumed by downstream stacks or pipeline steps
output "as3_gcs_bucket" {
  value       = local.as3_gcs_bucket
  description = "GCS bucket where AS3 declaration is stored"
}

output "as3_gcs_path" {
  value       = var.as3_gcs_path
  description = "GCS object path (relative to bucket) for the AS3 declaration"
}

output "as3_gcs_uri" {
  value       = local.as3_gcs_uri
  description = "Full GCS URI where AS3 declaration is stored for BIG-IP to pull"
}

output "as3_declaration_uploaded" {
  value       = "AS3 declaration uploaded to ${local.as3_gcs_uri}"
  description = "Confirmation that AS3 declaration was uploaded to GCS"
}
