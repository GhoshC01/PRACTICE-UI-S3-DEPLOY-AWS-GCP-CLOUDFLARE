# Public GCS bucket and site/ file upload. No load balancer and no Cloud CDN.
# The prod workspace uses the prod bucket. Every other workspace uses dev values.

locals {
  is_prod     = terraform.workspace == "prod"
  environment = local.is_prod ? "prod" : var.environment
  bucket_name = local.is_prod ? "my-ui-prod-rajib-gcp" : var.bucket_name
  site_dir    = "${path.module}/../../site"

  mime_types = {
    html = "text/html; charset=utf-8"
    css  = "text/css; charset=utf-8"
    js   = "text/javascript; charset=utf-8"
    json = "application/json"
    png  = "image/png"
    jpg  = "image/jpeg"
    jpeg = "image/jpeg"
    svg  = "image/svg+xml"
    ico  = "image/x-icon"
    webp = "image/webp"
  }
}

resource "google_storage_bucket" "site" {
  name                        = local.bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = !local.is_prod

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html"
  }

  labels = {
    environment = local.environment
    managed_by  = "terraform"
  }
}

resource "google_storage_bucket_iam_member" "public" {
  bucket = google_storage_bucket.site.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_storage_bucket_object" "site" {
  for_each = fileset(local.site_dir, "**")

  name   = each.value
  bucket = google_storage_bucket.site.name
  source = "${local.site_dir}/${each.value}"
  content_type = lookup(
    local.mime_types,
    try(regex("\\.([^.]+)$", each.value)[0], ""),
    "application/octet-stream"
  )
  cache_control = each.value == "index.html" ? "no-cache" : "public, max-age=3600"
}
