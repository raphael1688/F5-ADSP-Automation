# Main

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

resource "random_id" "build_suffix" {
  byte_length = 2
}
