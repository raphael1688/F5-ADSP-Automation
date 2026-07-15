# Variables

variable "gcp_project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "gcp_region" {
  type        = string
  description = "GCP region (optional if you keep using gcp_region in tfvars for compatibility)"
  default     = "us-west1"
}

variable "project_prefix" {
  type = string
  #  default     = "demo"
  description = "This value is inserted at the beginning of each GCP object (alpha-numeric, no special character)"
}
variable "resource_owner" {
  type        = string
  description = "owner of the deployment, for tagging purposes"
  default     = "myName"
}
variable "cidr" {
  description = "the CIDR block for the Virtual Private Cloud (VPC) of the deployment"
  default     = "10.0.0.0/16"
  type        = string
  validation {
    condition     = can(regex("^([0-9]{1,3}.){3}[0-9]{1,3}($|/(16|24))$", var.cidr))
    error_message = "The value must conform to a CIDR block format."
  }
}
variable "create_nat_gateway" {
  type        = bool
  default     = false
  description = "Set to true if a NGW is needed"
}
variable "admin_src_addr" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Allowed Admin source CIDR (used by infra firewall rules)."
}
variable "k8s_ingress" {
  type    = bool
  default = false
}
variable "bigip" {
  type    = bool
  default = false
}
variable "gke" {
  type        = bool
  default     = false
  description = "Provision GKE-supporting networking: dedicated k8s subnet with pod/service secondary ranges and Cloud NAT for private nodes."
}

variable "k8s_cidr" {
  type        = string
  default     = "10.10.0.0/22"
  description = "Primary CIDR for the GKE node subnet (used only when gke = true)."
  validation {
    condition     = can(cidrnetmask(var.k8s_cidr))
    error_message = "k8s_cidr must be a valid CIDR block."
  }
}

variable "k8s_pods_cidr" {
  type        = string
  default     = "10.11.0.0/16"
  description = "Secondary CIDR for GKE pods (alias IP range)."
  validation {
    condition     = can(cidrnetmask(var.k8s_pods_cidr))
    error_message = "k8s_pods_cidr must be a valid CIDR block."
  }
}

variable "k8s_services_cidr" {
  type        = string
  default     = "10.12.0.0/20"
  description = "Secondary CIDR for GKE services (alias IP range)."
  validation {
    condition     = can(cidrnetmask(var.k8s_services_cidr))
    error_message = "k8s_services_cidr must be a valid CIDR block."
  }
}
