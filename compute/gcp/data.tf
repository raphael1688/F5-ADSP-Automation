# Remote state: reads foundational outputs from infra/gcp
data "terraform_remote_state" "infra" {
  backend = "gcs"
  config = {
    bucket = var.tf_state_bucket
    prefix = var.infra_state_prefix
  }
}
