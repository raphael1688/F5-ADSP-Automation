provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "kubernetes" {
  host                   = local.cluster_host
  cluster_ca_certificate = base64decode(local.cluster_ca_certificate)
  token                  = data.google_client_config.current.access_token
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster_host
    cluster_ca_certificate = base64decode(local.cluster_ca_certificate)
    token                  = data.google_client_config.current.access_token
  }
}
