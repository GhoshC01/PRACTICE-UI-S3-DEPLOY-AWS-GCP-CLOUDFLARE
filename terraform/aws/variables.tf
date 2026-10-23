# কী কী ইনপুট লাগবে। মানগুলো terraform.tfvars থেকে আসে।

variable "aws_region" {
  description = "AWS region for the site bucket. The workflow signs in to ap-south-1."
  type        = string
}

variable "environment" {
  description = "Deployment name: dev or prod."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}


variable "project_name" {
  description = "Short name used on CloudFront and resource tags."
  type        = string
  default     = "practice-ui"
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name for this environment's site files."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name."
  }
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete the bucket even when it still has files."
  type        = bool
  default     = false
}
