# CLAUDE.md

Static todo site deployed three ways: private S3 + CloudFront, a public GCS bucket, and Cloudflare Pages. `site/` is the only app. Terraform and Wrangler publish that folder. They do not build it.

Human setup steps live in `LOCAL-SETUP.md`. This file is the map of how the repo is wired.

## Layout

| Path | Role |
|---|---|
| `site/` | `index.html`, `styles.css`, `app.js`. The files that get uploaded. |
| `terraform/aws/` | S3 bucket, CloudFront, and the object upload. |
| `terraform/gcp/` | Public GCS bucket and the object upload. No load balancer, no Cloud CDN. |
| `terraform/cloudflare/` | Creates the Pages project only. Does not upload `site/`. |
| `scripts/deploy.sh` | Laptop deploy, then calls `scripts/validate.sh`. |
| `scripts/validate.sh` | Downloads the live files and compares sha256 with `site/`. |
| `.github/workflows/deploy.yml` | Push to `main` or `develop` deploys all three in parallel. |
| `.env.example` | Committed template. Real values go in `.env`, which is gitignored. |

## Environment mapping

AWS and GCP use Terraform workspaces. Cloudflare uses the Git branch. The names do not match one-to-one.

| | dev | prod |
|---|---|---|
| Git branch | `develop` | `main` |
| Terraform workspace | `default` | `prod` |
| GitHub Actions environment | `develop` | `prod` |
| AWS bucket | `my-ui-dev-rajib` | `my-ui-prod-rajib` |
| GCP bucket | `my-ui-dev-rajib-gcp` | `my-ui-prod-rajib-gcp` |
| Cloudflare branch | `develop` | `main` |
| Cloudflare URL | `https://develop.my-ui-rajib.pages.dev` | `https://my-ui-rajib.pages.dev` |

`terraform.workspace == "prod"` selects the prod bucket. Every other workspace, including `default`, uses the dev bucket from `terraform.tfvars`.

Cloudflare has no workspace switch. `production_branch` is `main`. Preview URLs are `https://<branch>.<project>.pages.dev`.

## Terraform style

Each stack is applied from its own directory with only:

```bash
terraform init
terraform plan
terraform apply
```

Keep that true:

- Backend bucket, key, and region are written in the `backend` block. No `-backend-config`, no `env/` directory, no partial backend.
- Inputs come from the committed `terraform.tfvars` in that directory. No `-var-file`.
- Pass `-input=false` from scripts so Terraform cannot prompt.
- `terraform.tfvars` and `.terraform.lock.hcl` stay tracked. State files and `.terraform/` stay ignored.
- Terraform `>= 1.10`. AWS and Google providers `~> 6.0`. Cloudflare provider `~> 5.0`.
- Prod bucket names are literals in `locals`, not a second tfvars file.

Do not create the state buckets. They already exist.

| Stack | Backend |
|---|---|
| AWS | S3 `my-tf-state-bucket-ui-static-page-practice`, key `aws/dev/terraform.tfstate`, region `ap-south-1` |
| GCP | GCS `tf-state-ui-practice-rajib`, prefix `gcp` |
| Cloudflare | Same S3 bucket, key `cloudflare/terraform.tfstate`, region `ap-south-1` |

The S3 backend still isolates workspaces. `default` uses the key as written. A named workspace is stored under the default `env:` prefix. Leave that AWS key as it is.

GCP state objects are `gcp/default.tfstate` and `gcp/prod.tfstate`.

## What each stack publishes

**AWS.** Private bucket, CloudFront with origin access control, objects uploaded from `site/`. `site_dir` is `abspath("${path.module}/../../site")`. HTML is `no-cache`. Other files are `public, max-age=300`. JavaScript is `text/javascript`. Outputs: `site_url` (CloudFront hostname), `bucket_name`, `distribution_id`. After apply, invalidate `/*` and wait until the invalidation finishes.

**GCP.** `uniform_bucket_level_access`, public `roles/storage.objectViewer` for `allUsers`, website index and 404 both `index.html`. `site_dir` is the relative path `"${path.module}/../../site"` with no `abspath`. `force_destroy` is true only when the workspace is not `prod`. `index.html` is `no-cache`. Other objects are `public, max-age=3600`. Region `asia-south1`. Project `ui-practice-rajib`. Output `site_url` ends with `/index.html`. Validation strips that suffix and then requests each file.

**Cloudflare.** `provider "cloudflare" {}` with no arguments. The API token comes only from `CLOUDFLARE_API_TOKEN`. Resource is `cloudflare_pages_project.site` (`account_id`, `name`, `production_branch`). `subdomain` is read-only and looks like `my-ui-rajib.pages.dev`. File upload is Wrangler:

```bash
npx wrangler pages deploy site \
  --project-name="$CLOUDFLARE_PROJECT_NAME" \
  --branch=<develop|main> \
  --commit-dirty=true
```

CI uses `cloudflare/wrangler-action@v3` with `pages deploy site --project-name=my-ui-rajib --branch=${{ github.ref_name }}`. On `develop`, `github.ref_name` is `develop`, not `dev`.

## Local scripts

`./scripts/deploy.sh <env> <target>`

- `env` is `dev` or `prod` (default `dev`). `target` is `aws`, `gcp`, `cloudflare`, or `all` (default `all`).
- Loads `.env` with `set -a; source .env; set +a`. If `.env` is missing, print `Copy .env.example to .env and fill it in` and exit.
- Name a missing variable. Never print its value. Never write a token into any file except `.env`.
- Prod deploy requires the current git branch to be `main`, then the user must type `prod`.
- An `EXIT` trap runs `terraform workspace select default` in both `terraform/aws` and `terraform/gcp`, including after an error and including a Cloudflare-only run. Do not leave the user on the `prod` workspace.
- Bash 3.2 (macOS) and Linux. No associative arrays, no `mapfile`. sha256 is `shasum -a 256` or `sha256sum`.

`./scripts/validate.sh` can run on its own. It curls each file under `site/` with no cache-busting query string, checks HTTP 200, checks content type, and compares sha256 to the local file. JavaScript may be `text/javascript` or `application/javascript`. Retry up to `VALIDATE_RETRIES` (10) with `VALIDATE_WAIT_SECONDS` (15) between tries. Exit 0 only when every file passes.

## CI

`.github/workflows/deploy.yml` on push to `main` or `develop`, plus `workflow_dispatch`.

- `main` sets `WORKSPACE=prod` and the GitHub environment `prod`. `develop` sets `WORKSPACE=default` and the environment `develop`.
- Auth is OIDC. AWS uses `secrets.AWS_ROLE_ARN`. GCP uses `secrets.GCP_WIF_PROVIDER` and `secrets.GCP_SA_EMAIL`. Cloudflare uses `secrets.CLOUDFLARE_API_TOKEN` and `secrets.CLOUDFLARE_ACCOUNT_ID`.
- The AWS job id is `deploy`. GCP is `gcp`. Cloudflare is `cloudflare`. They run in parallel.
- AWS and GCP run `terraform workspace select -or-create`.

Do not put long-lived cloud keys in the workflow.

## Secrets

Committed on purpose: project ids, bucket names, region, and the Cloudflare account id in `terraform/cloudflare/terraform.tfvars`.

Never commit: `CLOUDFLARE_API_TOKEN`, AWS secret keys, GCP service-account JSON, or `.env`. `.env.example` stays committed with an empty token.

## When changing this repo

- A new file in `site/` must be picked up by the existing `fileset` uploads. Set a content type the validator accepts: `text/html`, `text/css`, and `text/javascript` or `application/javascript`.
- Keep AWS private behind CloudFront. Keep GCP public on the bucket. Keep Cloudflare file upload in Wrangler, not in `cloudflare_pages_project`.
- Do not add a second tfvars file or a workspace-specific backend config to switch dev and prod.
- After a local prod deploy or a prod validate, both Terraform directories must be on `default` again.
- `LOCAL-SETUP.md` is the new-user runbook. Update it when a command in `scripts/deploy.sh` or `scripts/validate.sh` changes.
