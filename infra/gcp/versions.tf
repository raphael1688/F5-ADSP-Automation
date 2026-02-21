terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }

  # Backend is intentionally left unconfigured here.
  # In GitHub Actions, run:
  #   terraform init -backend-config="bucket=$TF_STATE_BUCKET" -backend-config="prefix=state/infra"
  backend "gcs" {}
}
