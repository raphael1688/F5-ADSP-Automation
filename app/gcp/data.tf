data "terraform_remote_state" "infra" {
  backend = "gcs"
  config = {
    bucket = var.tf_state_bucket
    prefix = var.infra_state_prefix
  }
}

data "terraform_remote_state" "k8s" {
  backend = "gcs"
  config = {
    bucket = var.tf_state_bucket
    prefix = var.k8s_state_prefix
  }
}

data "terraform_remote_state" "nic" {
  backend = "gcs"
  config = {
    bucket = var.tf_state_bucket
    prefix = var.nic_state_prefix
  }
}

data "google_client_config" "current" {}
