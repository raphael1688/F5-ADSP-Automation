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

# Remote state: NIC outputs (UC2 origin source)
data "terraform_remote_state" "nic" {
  count   = var.backend_nic ? 1 : 0
  backend = "gcs"
  config = {
    bucket = var.tf_state_bucket
    prefix = var.nic_state_prefix
  }
}
