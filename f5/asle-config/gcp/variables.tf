variable "gcp_project_id" {
  type        = string
  description = "GCP project id."
}

variable "gcp_region" {
  type        = string
  description = "GCP region."
  default     = "us-west1"
}

variable "tf_state_bucket" {
  type        = string
  description = "GCS bucket name used for Terraform remote state."
}

variable "infra_state_prefix" {
  type        = string
  description = "GCS prefix where infra state is stored."
  default     = "state/uc3/infra"
}

variable "bigip_base_state_prefix" {
  type        = string
  description = "GCS prefix where bigip-base state is stored."
  default     = "state/uc3/bigip-base"
}

variable "bundle_gcs_path" {
  type        = string
  description = "GCS object path (relative to the state bucket) where the ASLE config bundle is uploaded."
  default     = "artifacts/uc3/asle/bundle.json"
}

variable "bigip_onboard_name" {
  type        = string
  description = "Logical name ASLE uses to identify this BIG-IP."
  default     = "uc3-bigip"
}

variable "bigip_onboard_port" {
  type        = string
  description = "Management port ASLE targets when reaching the BIG-IP."
  default     = "443"
}

variable "bigip_onboard_user" {
  type        = string
  description = "BIG-IP user ASLE authenticates as."
  default     = "admin"
}
