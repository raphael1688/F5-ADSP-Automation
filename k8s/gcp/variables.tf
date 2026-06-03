variable "gcp_project_id" {
  type        = string
  description = "GCP project ID."
}

variable "gcp_region" {
  type        = string
  default     = "us-west1"
  description = "GCP region."
}

variable "gcp_zone" {
  type        = string
  default     = "us-west1-a"
  description = "GCP zone for the cluster (single-zone deployment)."
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

variable "admin_src_addr" {
  type        = list(string)
  default     = []
  description = "Source CIDRs allowed to reach the GKE control plane public endpoint."
}

variable "master_authorized_networks_extra" {
  type        = list(string)
  default     = []
  description = "Additional CIDRs allowed to reach the control plane (e.g., GitHub Actions runner ranges). Merged with admin_src_addr. If both are empty, the control plane endpoint is reachable from any IPv4 address."
}

variable "master_ipv4_cidr_block" {
  type        = string
  default     = "172.16.0.0/28"
  description = "Reserved /28 CIDR for the control plane VPC peering. Must not overlap with VPC subnets."
  validation {
    condition     = can(cidrnetmask(var.master_ipv4_cidr_block))
    error_message = "master_ipv4_cidr_block must be a valid CIDR."
  }
}

variable "release_channel" {
  type        = string
  default     = "REGULAR"
  description = "GKE release channel: RAPID, REGULAR, or STABLE."
  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR, or STABLE."
  }
}

variable "node_machine_type" {
  type        = string
  default     = "e2-standard-4"
  description = "GCE machine type for the primary node pool."
}

variable "node_count" {
  type        = number
  default     = 2
  description = "Node count in the primary node pool."
}

variable "node_disk_size_gb" {
  type        = number
  default     = 50
  description = "Boot disk size per node, in GB."
}

variable "node_disk_type" {
  type        = string
  default     = "pd-balanced"
  description = "Boot disk type per node."
}

variable "node_service_account" {
  type        = string
  description = "Service account email attached to GKE nodes. If empty, GKE falls back to the project's default Compute Engine SA."
  default     = ""
}
