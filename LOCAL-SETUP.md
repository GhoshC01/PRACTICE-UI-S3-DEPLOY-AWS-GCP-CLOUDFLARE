# New user: run the site from your laptop

Run every command from the repo root. `.env` stays on your machine. Do not commit it.

The AWS state bucket, the GCP project `ui-practice-rajib`, and the Cloudflare Pages project `my-ui-rajib` already exist. The script does not create them. Your account needs permission to update those resources.

## Install

- Terraform 1.10 or newer
- AWS CLI
- gcloud
- Node.js (with `npx`)
- curl
- git

If the scripts are not executable, run this once:

```bash
chmod +x scripts/deploy.sh scripts/validate.sh
```

## 1. Settings

```bash
cp .env.example .env
```

Set these two values in `.env`:

- `CLOUDFLARE_API_TOKEN` — an API token from the Cloudflare dashboard, with Pages Edit permission.
- `CLOUDFLARE_ACCOUNT_ID` — `938a13b5ef53e9491d0239883340342c`

The other values are already in `.env.example`:

- `AWS_PROFILE=default`
- `AWS_REGION=ap-south-1`
- `GCP_PROJECT_ID=ui-practice-rajib`
- `CLOUDFLARE_PROJECT_NAME=my-ui-rajib`

If you use a different AWS profile, change `AWS_PROFILE` in `.env`.

## 2. Log in

```bash
aws login
gcloud auth application-default login
```

Your Google account needs access to the `ui-practice-rajib` project.

## 3. Deploy dev to all three clouds

```bash
./scripts/deploy.sh dev all
```

That command:

- AWS: `terraform init`, the `default` workspace, `apply`, then a CloudFront invalidation for `/*`
- GCP: `terraform init` and `apply` in the `default` workspace
- Cloudflare: uploads `site/` to the `develop` branch (`https://develop.my-ui-rajib.pages.dev`)
- Then runs `./scripts/validate.sh dev all`

When the script exits, the AWS and GCP workspaces are back on `default`.

One target only:

```bash
./scripts/deploy.sh dev aws
./scripts/deploy.sh dev gcp
./scripts/deploy.sh dev cloudflare
```

## 4. Prod

You must be on the `main` branch. Any other branch stops the script.

```bash
git checkout main
./scripts/deploy.sh prod all
```

Type `prod` at the prompt. AWS and GCP then use the `prod` workspace, and Cloudflare deploys the `main` branch (`https://my-ui-rajib.pages.dev`). The workspaces return to `default` when the script exits.

Prod for one target:

```bash
./scripts/deploy.sh prod aws
./scripts/deploy.sh prod gcp
./scripts/deploy.sh prod cloudflare
```

## 5. Check only

To see whether the CDN is serving the current files, without deploying again:

```bash
./scripts/validate.sh dev all
./scripts/validate.sh prod aws
./scripts/validate.sh prod gcp
./scripts/validate.sh prod cloudflare
```

`index.html`, `styles.css`, and `app.js` are downloaded from the CDN. Each one must return HTTP 200, the right content type, and the same sha256 as the local file. A mismatch is retried every 15 seconds, up to 10 times. Exit code `0` means everything passed. Exit code `1` means something failed.
