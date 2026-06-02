data "terraform_remote_state" "infra" {
  backend = "gcs"
  config = {
    bucket = var.tf_state_bucket
    prefix = var.infra_state_prefix
  }
}

data "terraform_remote_state" "bigip_base" {
  backend = "gcs"
  config = {
    bucket = var.tf_state_bucket
    prefix = var.bigip_base_state_prefix
  }
}
