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

variable "namespace" {
  type        = string
  default     = "nginx-ingress"
  description = "Kubernetes namespace for the NIC release and its policy CRD."
}

variable "nginx_jwt" {
  type        = string
  sensitive   = true
  description = "NGINX Plus license JWT. Used for the license secret and as the docker registry username."
}

variable "nginx_registry" {
  type        = string
  default     = "private-registry.nginx.com"
  description = "NGINX private registry hostname used by the imagePullSecret."
}

variable "chart_version" {
  type        = string
  default     = "2.0.1"
  description = "Version of the helm.nginx.com/stable nginx-ingress chart."
}

variable "nic_image_repository" {
  type        = string
  default     = "private-registry.nginx.com/nginx-ic-nap-v5/nginx-plus-ingress"
  description = "Image repository for the NGINX Plus Ingress Controller with NAP V5."
}

variable "nic_image_tag" {
  type        = string
  default     = "4.0.1"
  description = "Image tag for the NGINX Plus Ingress Controller."
}

variable "nap_enforcer_image" {
  type        = string
  default     = "private-registry.nginx.com/nap/waf-enforcer"
  description = "NAP V5 enforcer sidecar image repository."
}

variable "nap_enforcer_tag" {
  type        = string
  default     = "5.4.0"
  description = "NAP V5 enforcer sidecar image tag."
}

variable "nap_config_mgr_image" {
  type        = string
  default     = "private-registry.nginx.com/nap/waf-config-mgr"
  description = "NAP V5 config manager sidecar image repository."
}

variable "nap_config_mgr_tag" {
  type        = string
  default     = "5.4.0"
  description = "NAP V5 config manager sidecar image tag."
}

variable "nic_crds_url" {
  type        = string
  default     = "https://raw.githubusercontent.com/nginx/kubernetes-ingress/v4.0.1/deploy/crds.yaml"
  description = "URL to the upstream NIC CRDs manifest. Must match the chart version."
}

variable "nap_bundle_subdir" {
  type        = string
  default     = "artifacts/uc2/nap"
  description = "Subdirectory inside the state bucket where the workflow uploads compiled NAP policy bundles."
}

variable "gcp_runtime_service_account_email" {
  type        = string
  description = "Email of the runtime service account NIC pods impersonate via Workload Identity for GCS reads."
}

variable "waf_policy_name" {
  type        = string
  default     = "waf-policy"
  description = "Name of the NIC Policy resource exposing the compiled NAP bundle to apps."
}
