# Pages hostnames. subdomain is the production host, for example my-ui-rajib.pages.dev.

output "project_name" {
  description = "Cloudflare Pages project name."
  value       = cloudflare_pages_project.site.name
}

output "prod_url" {
  description = "Production URL for the main branch."
  value       = "https://${cloudflare_pages_project.site.subdomain}"
}

output "develop_url" {
  description = "Preview URL for the develop branch."
  value       = "https://develop.${cloudflare_pages_project.site.subdomain}"
}
