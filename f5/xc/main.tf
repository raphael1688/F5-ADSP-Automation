provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "volterra" {
  url = var.api_url
}