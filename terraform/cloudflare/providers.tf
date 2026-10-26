# Terraform and Cloudflare Pages setup.
# State reuses the existing AWS S3 bucket. No -backend-config flag.
# The API token is read only from the CLOUDFLARE_API_TOKEN environment variable.

terraform {
  required_version = ">= 1.10"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "my-tf-state-bucket-ui-static-page-practice"
    key    = "cloudflare/terraform.tfstate"
    region = "ap-south-1"
  }
}

provider "cloudflare" {}
