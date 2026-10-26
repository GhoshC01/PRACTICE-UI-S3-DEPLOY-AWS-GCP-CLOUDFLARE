# Inputs. Values come from terraform.tfvars, which Terraform loads automatically.

variable "account_id" {
  description = "Cloudflare account that owns the Pages project."
  type        = string
}

variable "project_name" {
  description = "Pages project name. Lowercase letters, digits, and hyphens only."
  type        = string
}
