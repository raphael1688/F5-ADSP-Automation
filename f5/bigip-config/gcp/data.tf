data "terraform_remote_state" "infra" {
  backend = "gcs"
  config = {
    bucket = var.tf_state_bucket
    prefix = var.infra_state_prefix
  }
}

data "terraform_remote_state" "compute" {
  count   = var.backend_compute ? 1 : 0
  backend = "gcs"
  config = {
    bucket = var.tf_state_bucket
    prefix = var.compute_state_prefix
  }
}
