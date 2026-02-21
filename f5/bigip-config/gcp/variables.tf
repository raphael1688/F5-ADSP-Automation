# Variables

#GCP
variable "gcp_project_id" {
  type        = string
  description = "GCP project id."
}

variable "gcp_region" {
  type        = string
  default     = "us-west1"
  description = "GCP region."
}

# Remote state
variable "tf_state_bucket" {
  type        = string
  description = "GCS bucket name for Terraform remote state."
}

variable "infra_state_prefix" {
  type        = string
  description = "GCS prefix where infra state is stored."
  default     = "state/infra"
}

variable "compute_state_prefix" {
  type        = string
  description = "GCS prefix where compute state is stored."
  default     = "state/compute"
}

variable "backend_compute" {
  type        = bool
  description = "Whether to reference compute remote state for app server IP."
  default     = false
}

#BIG-IP
variable "f5_username" {
  type        = string
  description = "Admin username for BIG-IP."
  default     = "admin"
}

#AWAF Config
variable "awaf_config_payload" {
  type        = string
  description = "AWAF Policy AS3 payload file."
  default     = "../config/awaf-config.json"
}

#App Server
variable "app_server_ip" {
  type        = string
  description = "App server IP (can be auto-discovered from compute remote state if backend_compute enabled)."
  default     = ""
}

#AS3 GCS Upload
variable "as3_gcs_path" {
  type        = string
  description = "GCS path for AS3 declaration artifact (relative to state bucket)."
  default     = "artifacts/uc1/as3/awaf-declaration.json"
}
