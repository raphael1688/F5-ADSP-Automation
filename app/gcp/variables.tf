variable "gcp_project_id" {
  type        = string
  description = "GCP project ID."
}

variable "gcp_region" {
  type        = string
  default     = "us-west1"
  description = "GCP region."
}

variable "tf_state_bucket" {
  type        = string
  description = "GCS bucket name used for Terraform remote state."
}

variable "infra_state_prefix" {
  type        = string
  default     = "state/uc2/infra"
  description = "GCS prefix where infra state is stored."
}

variable "k8s_state_prefix" {
  type        = string
  default     = "state/uc2/k8s"
  description = "GCS prefix where k8s state is stored."
}

variable "nic_state_prefix" {
  type        = string
  default     = "state/uc2/nic"
  description = "GCS prefix where NIC + NAP state is stored."
}

variable "namespace" {
  type        = string
  default     = "comfy-capybara"
  description = "Namespace the comfy-capybara workload lives in."
}

variable "chart_repository" {
  type        = string
  default     = "oci://ghcr.io/knowbase/charts"
  description = "Helm OCI repository hosting the chart."
}

variable "chart_name" {
  type        = string
  default     = "comfy-capybara"
  description = "Chart name."
}

variable "chart_version" {
  type        = string
  default     = "0.1.0"
  description = "Pinned chart version."
}

variable "release_name" {
  type        = string
  default     = ""
  description = "Override release name. Empty derives <project_prefix>-comfy-<build_suffix>."
}

variable "app_host" {
  type        = string
  description = "FQDN exposed by the NIC VirtualServer. Becomes the XC origin host in the planned XC block."
}

variable "image_registry" {
  type        = string
  default     = ""
  description = "Override image.registry. Empty leaves the chart default (ghcr.io/knowbase)."
}

variable "image_tag" {
  type        = string
  default     = ""
  description = "Override image.tag. Empty leaves the chart default (chart appVersion)."
}

variable "image_pull_secret_name" {
  type        = string
  default     = ""
  description = "Name of a pre-existing imagePullSecret. Empty omits imagePullSecrets."
}

variable "vs_tls_enabled" {
  type        = bool
  default     = false
  description = "Enable TLS termination at the NIC VirtualServer."
}

variable "vs_tls_secret_name" {
  type        = string
  default     = ""
  description = "Existing TLS Secret name in the app namespace. Required when vs_tls_enabled is true."
}

variable "attach_waf_server_wide" {
  type        = bool
  default     = true
  description = "Attach the NIC waf-policy at the VirtualServer level (covers every route by default)."
}

variable "attach_waf_to_api_route" {
  type        = bool
  default     = true
  description = "Attach the NIC waf-policy at the /api route (overrides server-wide policies on that route)."
}
