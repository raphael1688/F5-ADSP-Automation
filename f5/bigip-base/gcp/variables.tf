#BIG-IP Base Variables

# Remote state bucket 
variable "tf_state_bucket" {
  type        = string
  description = "GCS bucket name used for Terraform remote state"
}

variable "infra_state_prefix" {
  type        = string
  description = "GCS prefix where infra state is stored"
  default     = "state/infra"
}

variable "bigip_config_state_prefix" {
  type        = string
  description = "GCS prefix where bigip-config state is stored (for reading as3_gcs_uri output)"
  default     = "state/bigip-config"
}

# GCP
variable "gcp_project_id" {
  type        = string
  description = "GCP project id."
}

variable "gcp_region" {
  type        = string
  default     = "us-west1"
  description = "GCP region."
}

variable "gcp_zone" {
  type        = string
  default     = "us-west1-a"
  description = "GCP zone (single zone deployment)."
}

variable "gcp_runtime_service_account_email" {
  type        = string
  default     = null
  description = "Service account email to attach to BIG-IP instance (pre-created; no IAM in TF)."
}

# BIG-IP / VM
variable "vm_name" {
  type        = string
  default     = ""
  description = "Optional override for BIG-IP instance name."
}

variable "image_name" {
  type        = string
  description = "BIG-IP image self-link/URI (Marketplace image or custom image)."
}

variable "machine_type" {
  type        = string
  default     = "n2-highmem-4"
  description = "GCE machine type for BIG-IP."
}

variable "min_cpu_platform" {
  type        = string
  default     = "Intel Cascade Lake"
  description = "Optional minimum CPU platform."
}

variable "disk_type" {
  type        = string
  default     = "pd-ssd"
  description = "Disk type."
}

variable "disk_size_gb" {
  type        = number
  default     = 120
  description = "Disk size in GB. (120GB recommended for multi-module provisioning)."
}

# BIG-IP credentials / onboarding inputs
variable "f5_username" {
  type        = string
  default     = "admin"
  description = "Admin username for BIG-IP."
}

variable "f5_ssh_publickey" {
  type        = string
  description = "Path to OpenSSH public key file for BIG-IP SSH access (must exist at plan time)."
}

# Secret Manager optional mode (default false)
variable "gcp_secret_manager_authentication" {
  type        = bool
  default     = false
  description = "If true, runtime-init will read ADMIN_PASS from Secret Manager. Otherwise a generated password is used."
}

variable "gcp_secret_id" {
  type        = string
  default     = null
  description = "Secret identifier used by runtime-init when Secret Manager auth is enabled."
}

# NIC count toggle (deprecated: hardcoded to single-NIC in locals.tf)
variable "nic_count" {
  type        = string
  default     = "false"
  description = "Deprecated: This module now uses single-NIC deployment. Value is ignored (hardcoded to 'false' in locals.tf)."
}

## Please check and update the latest DO URL from https://github.com/F5Networks/f5-declarative-onboarding/releases
# always point to a specific version in order to avoid inadvertent configuration inconsistency
variable "DO_URL" {
  description = "URL to download the BIG-IP Declarative Onboarding module"
  type        = string
  default     = "https://github.com/F5Networks/f5-declarative-onboarding/releases/download/v1.42.0/f5-declarative-onboarding-1.42.0-9.noarch.rpm"
}
## Please check and update the latest AS3 URL from https://github.com/F5Networks/f5-appsvcs-extension/releases/latest 
# always point to a specific version in order to avoid inadvertent configuration inconsistency
variable "AS3_URL" {
  description = "URL to download the BIG-IP Application Service Extension 3 (AS3) module"
  type        = string
  default     = "https://github.com/F5Networks/f5-appsvcs-extension/releases/download/v3.49.0/f5-appsvcs-3.49.0-6.noarch.rpm"
}

## Please check and update the latest TS URL from https://github.com/F5Networks/f5-telemetry-streaming/releases/latest 
# always point to a specific version in order to avoid inadvertent configuration inconsistency
variable "TS_URL" {
  description = "URL to download the BIG-IP Telemetry Streaming module"
  type        = string
  default     = "https://github.com/F5Networks/f5-telemetry-streaming/releases/download/v1.34.0/f5-telemetry-1.34.0-1.noarch.rpm"
}

## Please check and update the latest Failover Extension URL from https://github.com/F5Networks/f5-cloud-failover-extension/releases/latest 
# always point to a specific version in order to avoid inadvertent configuration inconsistency
variable "CFE_URL" {
  description = "URL to download the BIG-IP Cloud Failover Extension module"
  type        = string
  default     = "https://github.com/F5Networks/f5-cloud-failover-extension/releases/download/v2.0.2/f5-cloud-failover-2.0.2-2.noarch.rpm"
}

## Please check and update the latest FAST URL from https://github.com/F5Networks/f5-appsvcs-templates/releases/latest 
# always point to a specific version in order to avoid inadvertent configuration inconsistency
variable "FAST_URL" {
  description = "URL to download the BIG-IP FAST module"
  type        = string
  default     = "https://github.com/F5Networks/f5-appsvcs-templates/releases/download/v1.25.0/f5-appsvcs-templates-1.25.0-1.noarch.rpm"
}
## Please check and update the latest runtime init URL from https://github.com/F5Networks/f5-bigip-runtime-init/releases/latest
# always point to a specific version in order to avoid inadvertent configuration inconsistency
variable "INIT_URL" {
  description = "URL to download the BIG-IP runtime init"
  type        = string
  default     = "https://cdn.f5.com/product/cloudsolutions/f5-bigip-runtime-init/v2.0.1/dist/f5-bigip-runtime-init-2.0.1-1.gz.run"
}

# Optional explicit versions (if you don’t want URL parsing)
variable "DO_VER" {
  type        = string
  default     = ""
  description = "Optional explicit DO version (e.g., v1.34.0). If empty, parsed from DO_URL."
}
variable "AS3_VER" {
  type        = string
  default     = ""
  description = "Optional explicit AS3 version (e.g., v3.41.0). If empty, parsed from AS3_URL."
}
variable "TS_VER" {
  type        = string
  default     = ""
  description = "Optional explicit TS version (e.g., v1.32.0). If empty, parsed from TS_URL."
}
variable "CFE_VER" {
  type        = string
  default     = ""
  description = "Optional explicit CFE version (e.g., vX.Y.Z). If empty, parsed from CFE_URL."
}
variable "FAST_VER" {
  type        = string
  default     = ""
  description = "Optional explicit FAST version (e.g., v1.22.0). If empty, parsed from FAST_URL."
}

# Optional provisioning toggles used by your runtime-init template
# Your template checks for asm == "true" / apm == "true"
variable "asm" {
  type        = string
  default     = "none"
  description = "Set to 'true' to provision ASM (template conditional)."
}

variable "apm" {
  type        = string
  default     = "none"
  description = "Set to 'true' to provision APM (template conditional)."
}
