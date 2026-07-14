data "terraform_remote_state" "infra" {
  backend = "gcs"
  config = {
    bucket = var.tf_state_bucket
    prefix = var.infra_state_prefix
  }
}

data "google_compute_zones" "available" {
  status = "UP"
}

# Stable Container-Optimized OS Image
data "google_compute_image" "cos" {
  family  = "cos-stable"
  project = "cos-cloud"
}
