terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Backend configured via CLI args in GitHub Actions
  # terraform init -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="prefix=state/bigip-config"
  backend "gcs" {}
}
