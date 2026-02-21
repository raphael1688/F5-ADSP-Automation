terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Backend configured via CLI args in GitHub Actions
  # terraform init -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="prefix=state/bigip-base"
  backend "gcs" {}
}
