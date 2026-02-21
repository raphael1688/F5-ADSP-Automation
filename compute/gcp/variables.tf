variable "gcp_project_id" {
  type        = string
  description = "GCP project id to deploy into"
}

variable "gcp_region" {
  type        = string
  description = "GCP region (e.g., us-west1)"
  default = "us-west1"
}

variable "gcp_zone" {
  type        = string
  description = "GCP zone for the docker host (e.g., us-west1-a)"
  default = "us-west1-a"
}

variable "gcp_runtime_service_account_email" {
  type        = string
  description = "Email of the service account used by the runtime"
}

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

variable "machine_type" {
  type        = string
  description = "GCE machine type"
  default     = "e2-micro"
}

variable "boot_disk_gb" {
  type        = number
  description = "Boot disk size (GB)"
  default     = 10
}

variable "assign_public_ip" {
  type        = bool
  description = "Attach an external IP to the instance"
  default     = true
}

variable "enable_oslogin" {
  type        = bool
  description = "Enable OS Login (IAM-based SSH) on the instance"
  default     = false
}

variable "install_docker_compose" {
  type        = bool
  description = "Install docker compose plugin v2 on the host"
  default     = true
}

variable "enable_artifact_registry_pull" {
  type        = bool
  description = "Grant Artifact Registry Reader to the instance service account"
  default     = false
}

variable "additional_network_tag" {
  type        = string
  description = "Optional additional network tag for firewall targeting"
  default     = ""
}

variable "extra_startup_script" {
  type        = string
  description = "Optional shell script content executed after Docker is installed (base64 passed to startup)"
  default     = ""
}

variable "ssh_pub" {
  type        = string
  description = "Optional SSH public key to add to compute VMs. If empty, only the auto-generated key is used."
  default     = ""
}

variable "vm_create_crapi" {
  description = "If set to true, the example resource will be created."
  type        = bool
  default     = false
}

variable "vm_create_juice_shop" {
  description = "If set to true, the example resource will be created."
  type        = bool
  default     = false
}
