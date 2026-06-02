# bigip-config.tf
# Uploads AS3 declaration to GCS for BIG-IP to pull and apply

# Upload AS3 declaration to GCS
# BIG-IP will pull this artifact during post_onboard_enabled phase
resource "google_storage_bucket_object" "as3_declaration" {
  name    = var.as3_gcs_path
  bucket  = local.as3_gcs_bucket
  content = local.as3_declaration

  source_md5hash = md5(local.as3_declaration)
}

