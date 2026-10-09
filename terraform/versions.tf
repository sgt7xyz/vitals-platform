terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
  }

  # Bucket is passed at init time so the same code works in every environment:
  #   terraform init -backend-config="bucket=<PROJECT_ID>-tfstate"
  backend "gcs" {
    prefix = "vitals-platform/dev"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  # Every resource that supports labels gets these. Auditors and FinOps both rely on them.
  default_labels = {
    env        = var.env
    owner      = "platform"
    managed-by = "terraform"
    system     = "vitals-platform"
  }
}

data "google_project" "this" {}
