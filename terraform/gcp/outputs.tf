# Site address after apply.

output "bucket_name" {
  description = "GCS bucket that holds the uploaded site files."
  value       = google_storage_bucket.site.name
}

output "site_url" {
  description = "Public URL of the site index served directly from the bucket."
  value       = "https://storage.googleapis.com/${google_storage_bucket.site.name}/index.html"
}
