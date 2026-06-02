provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

resource "google_storage_bucket_object" "bundle" {
  name    = var.bundle_gcs_path
  bucket  = var.tf_state_bucket
  content = jsonencode(local.bundle)

  source_md5hash = md5(jsonencode(local.bundle))
}
