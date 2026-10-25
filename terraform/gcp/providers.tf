# Terraform and Google Cloud setup.
# State lives in an existing GCS bucket. No -backend-config flag.

terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  backend "gcs" {
    bucket = "tf-state-ui-practice-rajib"
    prefix = "gcp"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
