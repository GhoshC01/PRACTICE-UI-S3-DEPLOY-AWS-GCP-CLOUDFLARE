# One Cloudflare Pages project. Wrangler uploads site/ later.
# Pages maps production to main and other branches to preview URLs.

resource "cloudflare_pages_project" "site" {
  account_id        = var.account_id
  name              = var.project_name
  production_branch = "main"
}
