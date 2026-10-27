# PRACTICE-UI-S3-DEPLOY-AWS-GCP-CLOUDFLARE

## Local deployment

New users: follow [LOCAL-SETUP.md](LOCAL-SETUP.md).

Secrets and settings live in `.env`. That file stays on your machine.

```bash
cp .env.example .env
```

Fill in `.env`, then log in:

```bash
aws login
gcloud auth application-default login
```

Deploy and validate:

```bash
./scripts/deploy.sh dev all
./scripts/deploy.sh prod aws
./scripts/validate.sh dev all
```

`dev` uses the Terraform `default` workspace and the Cloudflare `develop` branch. `prod` uses the `prod` workspace and the `main` branch. A prod deploy must be run from git branch `main`, and the script asks you to type `prod` before it continues. When the script exits, both Terraform directories are switched back to the `default` workspace.
