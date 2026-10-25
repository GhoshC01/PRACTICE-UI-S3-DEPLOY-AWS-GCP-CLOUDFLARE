# Inputs. Values come from terraform.tfvars, which Terraform loads automatically.

variable "project_id" {
  description = "GCP project that owns the site bucket."
  type        = string
}

variable "region" {
  description = "GCS location for the site bucket."
  type        = string
  default     = "asia-south1"
}

variable "environment" {
  description = "Deployment name used when the workspace is not prod."
  type        = string
  default     = "dev"
}

variable "bucket_name" {
  description = "Globally unique GCS bucket name for this environment's site files."
  type        = string
}
