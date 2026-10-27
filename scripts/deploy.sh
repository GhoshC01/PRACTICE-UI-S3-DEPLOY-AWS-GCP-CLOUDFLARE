#!/usr/bin/env bash
# Deploy the static site from a laptop, then validate the CDN.
# Usage: ./scripts/deploy.sh <env> <target>
#   env    = dev | prod                         (default: dev)
#   target = aws | gcp | cloudflare | all       (default: all)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BLUE=$'\033[34m'
  C_YELLOW=$'\033[33m'
  C_MAGENTA=$'\033[35m'
  C_BOLD=$'\033[1m'
else
  C_RESET=""
  C_BLUE=""
  C_YELLOW=""
  C_MAGENTA=""
  C_BOLD=""
fi

log() {
  local provider="$1"
  shift
  local color="$C_BOLD"
  case "$provider" in
    aws) color="$C_BLUE" ;;
    gcp) color="$C_YELLOW" ;;
    cloudflare) color="$C_MAGENTA" ;;
  esac
  printf '%s[%s]%s %s\n' "$color" "$provider" "$C_RESET" "$*" >&2
}

die() {
  log deploy "$*"
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./scripts/deploy.sh <env> <target>
  env    = dev | prod                         (default: dev)
  target = aws | gcp | cloudflare | all       (default: all)
EOF
}

load_env() {
  if [[ ! -f "$ROOT/.env" ]]; then
    echo "Copy .env.example to .env and fill it in"
    exit 1
  fi
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
}

MISSING_VARS=0

require_var() {
  local name value
  for name in "$@"; do
    value="${!name-}"
    if [[ -z "$value" ]]; then
      printf 'Missing required variable: %s\n' "$name"
      MISSING_VARS=1
    fi
  done
}

require_non_negative_integer() {
  local name="$1"
  local value="${!name-}"
  case "$value" in
    ''|*[!0-9]*)
      printf '%s must be a non-negative integer\n' "$name"
      exit 1
      ;;
  esac
}

need_cmd() {
  local cmd missing=0
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      printf 'Missing command: %s\n' "$cmd"
      missing=1
    fi
  done
  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi
}

workspace_for() {
  if [[ "$1" == "prod" ]]; then
    printf '%s\n' "prod"
  else
    printf '%s\n' "default"
  fi
}

reset_workspace() {
  local dir="$1"
  local label="$2"
  if [[ -d "$dir/.terraform" ]]; then
    if terraform -chdir="$dir" workspace select default >/dev/null; then
      log "$label" "Workspace is default."
    else
      log deploy "Warning: could not switch ${dir#$ROOT/} back to the default workspace."
    fi
  fi
}

cleanup() {
  local status=$?
  set +e
  log deploy "Switching Terraform workspaces back to default."
  reset_workspace "$ROOT/terraform/aws" "aws"
  reset_workspace "$ROOT/terraform/gcp" "gcp"
  exit "$status"
}

confirm_prod() {
  local branch confirm
  if ! command -v git >/dev/null 2>&1; then
    die "Missing command: git"
  fi
  branch="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$branch" != "main" ]]; then
    die "Refusing prod deploy from branch '${branch}'. Check out main first."
  fi
  if [[ ! -r /dev/tty ]]; then
    die "Prod deploy needs an interactive terminal so you can type prod to confirm."
  fi
  printf 'Type "prod" to confirm production deployment: ' >/dev/tty
  IFS= read -r confirm </dev/tty || true
  if [[ "$confirm" != "prod" ]]; then
    die "Aborted. Production deployment was not confirmed."
  fi
  log deploy "Production deployment confirmed on branch main."
}

preflight() {
  need_cmd terraform aws gcloud node npx curl
  log aws "Checking AWS login."
  if ! aws sts get-caller-identity >/dev/null; then
    die "AWS login failed. Check AWS_PROFILE and sign in."
  fi
  log aws "AWS login ok."
  log gcp "Checking GCP application-default login."
  # stdout is the access token. Discard it and never print it.
  if ! gcloud auth application-default print-access-token >/dev/null; then
    die "GCP login failed. Run: gcloud auth application-default login"
  fi
  log gcp "GCP login ok."
}

select_workspace() {
  local dir="$1"
  local ws="$2"
  local label="$3"
  log "$label" "Selecting workspace ${ws}."
  terraform -chdir="$dir" workspace select -or-create "$ws" >/dev/null
}

deploy_aws() {
  local dir="$ROOT/terraform/aws"
  local ws distribution_id site_url invalidation_id
  ws="$(workspace_for "$ENV_NAME")"
  log aws "terraform init"
  terraform -chdir="$dir" init -input=false
  select_workspace "$dir" "$ws" "aws"
  log aws "terraform apply (workspace ${ws})"
  terraform -chdir="$dir" apply -auto-approve -input=false
  distribution_id="$(terraform -chdir="$dir" output -raw distribution_id)"
  site_url="$(terraform -chdir="$dir" output -raw site_url)"
  log aws "site_url ${site_url}"
  log aws "Creating CloudFront invalidation for /*"
  invalidation_id="$(aws cloudfront create-invalidation \
    --distribution-id "$distribution_id" \
    --paths "/*" \
    --query 'Invalidation.Id' \
    --output text)"
  log aws "Invalidation id ${invalidation_id}"
  log aws "Waiting for invalidation ${invalidation_id} to complete."
  aws cloudfront wait invalidation-completed \
    --distribution-id "$distribution_id" \
    --id "$invalidation_id"
  log aws "Invalidation ${invalidation_id} completed."
}

deploy_gcp() {
  local dir="$ROOT/terraform/gcp"
  local ws site_url
  ws="$(workspace_for "$ENV_NAME")"
  log gcp "terraform init"
  terraform -chdir="$dir" init -input=false
  select_workspace "$dir" "$ws" "gcp"
  log gcp "terraform apply (workspace ${ws})"
  terraform -chdir="$dir" apply -auto-approve -input=false
  site_url="$(terraform -chdir="$dir" output -raw site_url)"
  log gcp "site_url ${site_url}"
}

deploy_cloudflare() {
  local branch="develop"
  if [[ "$ENV_NAME" == "prod" ]]; then
    branch="main"
  fi
  log cloudflare "npx wrangler pages deploy site --project-name=${CLOUDFLARE_PROJECT_NAME} --branch=${branch} --commit-dirty=true"
  npm_config_yes=true npx wrangler pages deploy site \
    --project-name="$CLOUDFLARE_PROJECT_NAME" \
    --branch="$branch" \
    --commit-dirty=true
}

ENV_NAME="${1:-dev}"
TARGET="${2:-all}"

case "$ENV_NAME" in
  dev|prod) ;;
  *)
    usage
    exit 1
    ;;
esac

case "$TARGET" in
  aws|gcp|cloudflare|all) ;;
  *)
    usage
    exit 1
    ;;
esac

load_env

require_var VALIDATE_RETRIES VALIDATE_WAIT_SECONDS
case "$TARGET" in
  aws)
    require_var AWS_PROFILE AWS_REGION
    ;;
  gcp)
    require_var GCP_PROJECT_ID
    ;;
  cloudflare)
    require_var CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_PROJECT_NAME
    ;;
  all)
    require_var AWS_PROFILE AWS_REGION GCP_PROJECT_ID \
      CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_PROJECT_NAME
    ;;
esac
if [[ "$MISSING_VARS" -ne 0 ]]; then
  exit 1
fi
require_non_negative_integer VALIDATE_RETRIES
require_non_negative_integer VALIDATE_WAIT_SECONDS
if [[ "$((10#$VALIDATE_RETRIES))" -lt 1 ]]; then
  echo "VALIDATE_RETRIES must be at least 1"
  exit 1
fi

preflight

if [[ "$ENV_NAME" == "prod" ]]; then
  confirm_prod
fi

trap cleanup EXIT

case "$TARGET" in
  aws) deploy_aws ;;
  gcp) deploy_gcp ;;
  cloudflare) deploy_cloudflare ;;
  all)
    deploy_aws
    deploy_gcp
    deploy_cloudflare
    ;;
esac

log deploy "Running validation."
"$ROOT/scripts/validate.sh" "$ENV_NAME" "$TARGET"
