terraform {
  required_version = ">= 1.3.0"

  required_providers {
    volterra = {
      source  = "volterraedge/volterra"
      version = ">= 0.11.47"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }

  backend "gcs" {
  }
}
