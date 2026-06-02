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
  default     = "state/uc1/infra"
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

variable "vm_create_comfy_capybara" {
  description = "Provision the comfy-capybara docker host."
  type        = bool
  default     = false
}

variable "vm_create_asle" {
  description = "Provision the ASLE docker host."
  type        = bool
  default     = false
}

variable "comfy_compose_artifact" {
  description = "OCI artifact reference for the comfy-capybara compose."
  type        = string
  default     = "ghcr.io/knowbase/comfy-capybara-compose"
}

variable "comfy_compose_tag" {
  description = "Tag of the comfy-capybara compose artifact."
  type        = string
  default     = "0.3.0"
}

variable "oras_image" {
  description = "Docker image for the ORAS CLI."
  type        = string
  default     = "ghcr.io/oras-project/oras:v1.2.0"
}

variable "docker_compose_plugin_url" {
  description = "URL of the docker compose v2 plugin binary."
  type        = string
  default     = "https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64"
}

variable "asle_tarball_gcs_uri" {
  description = "Fully qualified gs:// URI to the ASLE image tarball."
  type        = string
  default     = ""
}

variable "asle_image_ref" {
  description = "Image reference (repository:tag) that docker load materializes from the tarball."
  type        = string
  default     = ""
}

variable "asle_management_port" {
  description = "Port the ASLE management UI listens on."
  type        = number
  default     = 8000
}

variable "asle_telemetry_port" {
  description = "Port the ASLE telemetry collector listens on."
  type        = number
  default     = 0
}

variable "asle_machine_type" {
  description = "GCE machine type for the ASLE docker host."
  type        = string
  default     = "e2-custom-2-4096"
}

variable "asle_boot_disk_gb" {
  description = "Boot disk size (GB) for the ASLE docker host."
  type        = number
  default     = 30
}

variable "asle_config_bundle_gcs_uri" {
  description = "gs:// URI of the ASLE config bundle the on-VM poller watches. Empty disables the poller."
  type        = string
  default     = ""
}

variable "asle_poller_image" {
  description = "Docker image used by the on-VM poller."
  type        = string
  default     = "google/cloud-sdk:slim"
}

variable "asle_poller_interval_seconds" {
  description = "Seconds between poll cycles."
  type        = number
  default     = 30
}
