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
  default     = "state/uc1/infra"
}

variable "compute_state_prefix" {
  type        = string
  description = "GCS prefix where compute state is stored."
  default     = "state/uc1/compute"
}

variable "backend_compute" {
  type        = bool
  description = "Whether to reference compute remote state for app server IP."
  default     = false
}

variable "bigip_base_state_prefix" {
  type        = string
  description = "GCS prefix where bigip-base state is stored."
  default     = "state/uc3/bigip-base"
}

variable "backend_bigip_base" {
  type        = bool
  description = "Whether to reference bigip-base remote state."
  default     = false
}

variable "app_server_port" {
  type        = number
  description = "Backend application service port."
  default     = 80
}

variable "api_server_port" {
  type        = number
  description = "API service port for path-routed traffic (/docs, /openapi.json, /redoc)."
  default     = 8000
}

variable "asle_telemetry_port" {
  type        = number
  description = "Port the ASLE telemetry collector listens on."
  default     = 0
}

variable "self_signed_cert_cn" {
  type        = string
  description = "Common Name for the self-signed front-door TLS certificate."
  default     = "bigip-front-door"
}

variable "self_signed_cert_validity_hours" {
  type        = number
  description = "Validity period of the self-signed cert in hours."
  default     = 8760
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
  description = "AS3 payload template file (relative to the module)."
  default     = "../config/uc1-config.json"
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
