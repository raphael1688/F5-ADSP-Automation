#BIG-IP Base Variables

# Remote state bucket 
variable "tf_state_bucket" {
  type        = string
  description = "GCS bucket name used for Terraform remote state"
}

variable "infra_state_prefix" {
  type        = string
  description = "GCS prefix where infra state is stored"
  default     = "state/uc1/infra"
}

variable "bigip_config_state_prefix" {
  type        = string
  description = "GCS prefix where bigip-config state is stored. Read only when as3_gcs_uri is empty."
  default     = "state/uc1/bigip-config"
}

variable "as3_gcs_uri" {
  type        = string
  description = "Fully qualified gs:// URI of the AS3 declaration the BIG-IP polls on boot."
  default     = ""
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

# Deprecated. Single-NIC is hardcoded in locals.tf; this value is ignored.
variable "nic_count" {
  type        = string
  default     = "false"
  description = "Deprecated. Single-NIC is hardcoded in locals.tf."
}

variable "DO_URL" {
  description = "URL to download the BIG-IP Declarative Onboarding module"
  type        = string
  default     = "https://github.com/F5Networks/f5-declarative-onboarding/releases/download/v1.42.0/f5-declarative-onboarding-1.42.0-9.noarch.rpm"
}

variable "AS3_URL" {
  description = "URL to download the BIG-IP Application Service Extension 3 (AS3) module"
  type        = string
  default     = "https://github.com/F5Networks/f5-appsvcs-extension/releases/download/v3.49.0/f5-appsvcs-3.49.0-6.noarch.rpm"
}

variable "TS_URL" {
  description = "URL to download the BIG-IP Telemetry Streaming module"
  type        = string
  default     = "https://github.com/F5Networks/f5-telemetry-streaming/releases/download/v1.34.0/f5-telemetry-1.34.0-1.noarch.rpm"
}

variable "CFE_URL" {
  description = "URL to download the BIG-IP Cloud Failover Extension module"
  type        = string
  default     = "https://github.com/F5Networks/f5-cloud-failover-extension/releases/download/v2.0.2/f5-cloud-failover-2.0.2-2.noarch.rpm"
}

variable "FAST_URL" {
  description = "URL to download the BIG-IP FAST module"
  type        = string
  default     = "https://github.com/F5Networks/f5-appsvcs-templates/releases/download/v1.25.0/f5-appsvcs-templates-1.25.0-1.noarch.rpm"
}

variable "INIT_URL" {
  description = "URL to download the BIG-IP runtime init"
  type        = string
  default     = "https://cdn.f5.com/product/cloudsolutions/f5-bigip-runtime-init/v2.0.1/dist/f5-bigip-runtime-init-2.0.1-1.gz.run"
}

variable "DO_VER" {
  type        = string
  default     = ""
  description = "Explicit DO version override. Parsed from DO_URL when empty."
}
variable "AS3_VER" {
  type        = string
  default     = ""
  description = "Explicit AS3 version override. Parsed from AS3_URL when empty."
}
variable "TS_VER" {
  type        = string
  default     = ""
  description = "Explicit TS version override. Parsed from TS_URL when empty."
}
variable "CFE_VER" {
  type        = string
  default     = ""
  description = "Explicit CFE version override. Parsed from CFE_URL when empty."
}
variable "FAST_VER" {
  type        = string
  default     = ""
  description = "Explicit FAST version override. Parsed from FAST_URL when empty."
}

variable "asm" {
  type        = string
  default     = "none"
  description = "ASM provisioning level passed to the runtime-init DO declaration."
}

variable "apm" {
  type        = string
  default     = "none"
  description = "APM provisioning level passed to the runtime-init DO declaration."
}
