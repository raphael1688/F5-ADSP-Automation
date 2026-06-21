data "terraform_remote_state" "infra" {
  backend = "gcs"
  config = {
    bucket = var.tf_state_bucket
    prefix = var.infra_state_prefix
  }
}

# Remote state: BIG-IP outputs
data "terraform_remote_state" "bigip" {
  count = var.backend_bigip ? 1 : 0
  backend = "gcs"
  config = {
    bucket = var.tf_state_bucket
    prefix = var.bigip_state_prefix
  }
}

# Remote state: ingress data-plane outputs (origin source)
data "terraform_remote_state" "k8s_ingress" {
  count   = var.backend_k8s_ingress ? 1 : 0
  backend = "gcs"
  config = {
    bucket = var.tf_state_bucket
    prefix = var.k8s_ingress_state_prefix
  }
}

# Check if the namespace in XC already exists
data "volterra_namespace" "existing" {
  name = var.xc_namespace
}
