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
variable "mgmt_address_prefixes" {
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.100.0/24"]
  description = "Management subnet address prefixes"
}
variable "ext_address_prefixes" {
  type        = list(string)
  default     = ["10.1.10.0/24", "10.1.110.0/24"]
  description = "External subnet address prefixes"
}
variable "int_address_prefixes" {
  type        = list(string)
  default     = ["10.1.20.0/24", "10.1.120.0/24"]
  description = "Internal subnet address prefixes"
}
variable "nap" {
  type    = bool
  default = false
}
variable "nic" {
  type    = bool
  default = false
}
variable "bigip" {
  type    = bool
  default = false
}
variable "bigip_cis" {
  type    = bool
  default = false
}
