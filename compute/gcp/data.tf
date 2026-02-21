# Remote state: reads foundational outputs from infra/gcp
data "terraform_remote_state" "infra" {
  backend = "gcs"
  config = {
    bucket = var.tf_state_bucket
    prefix = var.infra_state_prefix
  }
}

# Latest Ubuntu LTS image (stable default for Docker host)
data "google_compute_image" "ubuntu_lts" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}
