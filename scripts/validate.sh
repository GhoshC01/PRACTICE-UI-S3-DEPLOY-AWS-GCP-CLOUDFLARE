#!/usr/bin/env bash
# Check that each CDN is serving the files in site/ unchanged.
# Usage: ./scripts/validate.sh <env> <target>
#   env    = dev | prod                         (default: dev)
#   target = aws | gcp | cloudflare | all       (default: all)
#
# JavaScript is accepted as application/javascript or text/javascript.
# AWS and GCP objects are uploaded as text/javascript. Wrangler often
# sends application/javascript. Both are the same script type.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_BLUE=$'\033[34m'
  C_YELLOW=$'\033[33m'
  C_MAGENTA=$'\033[35m'
  C_BOLD=$'\033[1m'
else
  C_RESET=""
  C_RED=""
  C_GREEN=""
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

usage() {
  cat <<'EOF'
Usage: ./scripts/validate.sh <env> <target>
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
FAILURES=0
TOUCHED_AWS=0
TOUCHED_GCP=0
WORKDIR=""
RESULTS=""

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
    if ! terraform -chdir="$dir" workspace select default >/dev/null; then
      log validate "Warning: could not switch ${dir#$ROOT/} back to the default workspace."
    else
      log "$label" "Workspace is default."
    fi
  fi
}

cleanup() {
  local status=$?
  set +e
  if [[ "$TOUCHED_AWS" -eq 1 || "$TOUCHED_GCP" -eq 1 ]]; then
    log validate "Switching Terraform workspaces back to default."
  fi
  if [[ "$TOUCHED_AWS" -eq 1 ]]; then
    reset_workspace "$ROOT/terraform/aws" "aws"
  fi
  if [[ "$TOUCHED_GCP" -eq 1 ]]; then
    reset_workspace "$ROOT/terraform/gcp" "gcp"
  fi
  if [[ -n "$WORKDIR" ]]; then
    rm -rf "$WORKDIR"
  fi
  exit "$status"
}

hash_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    echo "Missing command: shasum or sha256sum" >&2
    return 1
  fi
}

header_lookup() {
  local name="$1"
  local file="$2"
  local line
  line="$(grep -i "^${name}:" "$file" 2>/dev/null | tail -n 1 || true)"
  if [[ -z "$line" ]]; then
    return 0
  fi
  printf '%s\n' "$line" | cut -d: -f2- | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

media_type() {
  printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]' | cut -d';' -f1 | tr -d '[:space:]' | tr -d '"'
}

content_type_ok() {
  local file="$1"
  local got="$2"
  local media
  media="$(media_type "$got")"
  case "$file" in
    *.html|*.htm)
      [[ "$media" == "text/html" ]]
      ;;
    *.css)
      [[ "$media" == "text/css" ]]
      ;;
    *.js)
      [[ "$media" == "application/javascript" || "$media" == "text/javascript" ]]
      ;;
    *)
      return 1
      ;;
  esac
}

expected_type_label() {
  case "$1" in
    *.html|*.htm) printf '%s\n' "text/html" ;;
    *.css) printf '%s\n' "text/css" ;;
    *.js) printf '%s\n' "application/javascript or text/javascript" ;;
    *) printf '%s\n' "unknown" ;;
  esac
}

cache_bits() {
  local cache_control="$1"
  local age="$2"
  local x_cache="$3"
  local cf_status="$4"
  local extra=""
  if [[ -n "$cache_control" ]]; then
    extra="${extra} cache-control=${cache_control}"
  fi
  if [[ -n "$age" ]]; then
    extra="${extra} age=${age}"
  fi
  if [[ -n "$x_cache" ]]; then
    extra="${extra} x-cache=${x_cache}"
  fi
  if [[ -n "$cf_status" ]]; then
    extra="${extra} cf-cache-status=${cf_status}"
  fi
  printf '%s\n' "$extra"
}

record() {
  printf '%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" >>"$RESULTS"
  if [[ "$5" != "PASS" ]]; then
    FAILURES=$((FAILURES + 1))
  fi
}

check_provider_files() {
  local provider="$1"
  local base_url="$2"
  local path file local_hash remote_hash url body headers
  local attempt status ctype cache_control age x_cache cf_status
  local content_result reason max_age bits type_ok hash_ok hash_label passed

  base_url="${base_url%/}"
  log "$provider" "Checking ${base_url}"
  body="${WORKDIR}/body"
  headers="${WORKDIR}/headers"

  for path in "$ROOT/site"/*; do
    if [[ ! -f "$path" ]]; then
      continue
    fi
    file="$(basename "$path")"
    local_hash="$(hash_file "$path")"
    url="${base_url}/${file}"
    content_result="error"
    reason="no response"
    status="000"
    passed=0

    attempt=1
    while [[ "$attempt" -le "$VALIDATE_RETRIES" ]]; do
      status="000"
      ctype=""
      cache_control=""
      age=""
      x_cache=""
      cf_status=""
      : >"$headers"
      : >"$body"

      status="$(curl --silent --show-error --location --max-redirs 5 \
        --dump-header "$headers" \
        --output "$body" \
        --write-out "%{http_code}" \
        "$url" || true)"
      if [[ -z "$status" ]]; then
        status="000"
      fi

      ctype="$(header_lookup "content-type" "$headers")"
      cache_control="$(header_lookup "cache-control" "$headers")"
      age="$(header_lookup "age" "$headers")"
      x_cache="$(header_lookup "x-cache" "$headers")"
      cf_status="$(header_lookup "cf-cache-status" "$headers")"
      bits="$(cache_bits "$cache_control" "$age" "$x_cache" "$cf_status")"

      type_ok=0
      hash_ok=0
      if content_type_ok "$file" "$ctype"; then
        type_ok=1
      fi
      remote_hash="$(hash_file "$body")"
      if [[ "$remote_hash" == "$local_hash" ]]; then
        hash_ok=1
      fi

      if [[ "$hash_ok" -eq 1 ]]; then
        hash_label="match"
      else
        hash_label="differ"
      fi
      log "$provider" "${file} attempt ${attempt}/${VALIDATE_RETRIES} status=${status} content-type=${ctype:-none} sha256=${hash_label}${bits}"

      if [[ "$status" == "200" && "$type_ok" -eq 1 && "$hash_ok" -eq 1 ]]; then
        passed=1
        record "$provider" "$file" "$status" "match" "PASS"
        break
      fi

      if [[ "$status" != "200" ]]; then
        content_result="error"
        reason="HTTP ${status}"
      elif [[ "$type_ok" -ne 1 ]]; then
        content_result="bad-type"
        reason="content-type '${ctype:-none}' is not $(expected_type_label "$file")"
      else
        content_result="stale"
        reason="sha256 does not match the local file"
        max_age="$(printf '%s\n' "$cache_control" | sed -n 's/.*max-age=\([0-9][0-9]*\).*/\1/p')"
        if [[ -n "$max_age" ]]; then
          reason="${reason}; cache-control max-age=${max_age} so a cached copy can be served for ${max_age}s"
        elif [[ -n "$cache_control" ]]; then
          reason="${reason}; cache-control=${cache_control}"
        fi
      fi

      if [[ "$attempt" -lt "$VALIDATE_RETRIES" ]]; then
        log "$provider" "Waiting ${VALIDATE_WAIT_SECONDS}s before retrying ${file}."
        sleep "$VALIDATE_WAIT_SECONDS"
      fi
      attempt=$((attempt + 1))
    done

    if [[ "$passed" -ne 1 ]]; then
      log "$provider" "FAIL ${file}: ${reason}"
      record "$provider" "$file" "$status" "$content_result" "FAIL"
    fi
  done
}

use_workspace() {
  local dir="$1"
  local ws="$2"
  local label="$3"
  log "$label" "Selecting workspace ${ws} to read site_url."
  terraform -chdir="$dir" workspace select "$ws" >/dev/null
}

validate_aws() {
  local dir="$ROOT/terraform/aws"
  local ws site_url
  need_cmd terraform aws
  log aws "Checking AWS login."
  if ! aws sts get-caller-identity >/dev/null; then
    log aws "AWS login failed. Check AWS_PROFILE and sign in."
    record "aws" "-" "-" "error" "FAIL"
    return 0
  fi
  ws="$(workspace_for "$ENV_NAME")"
  TOUCHED_AWS=1
  if ! site_url="$(use_workspace "$dir" "$ws" "aws" && terraform -chdir="$dir" output -raw site_url)"; then
    log aws "Could not read site_url from workspace ${ws}."
    record "aws" "-" "-" "error" "FAIL"
    return 0
  fi
  if [[ -z "$site_url" ]]; then
    log aws "site_url from workspace ${ws} is empty."
    record "aws" "-" "-" "error" "FAIL"
    return 0
  fi
  check_provider_files "aws" "$site_url"
}

validate_gcp() {
  local dir="$ROOT/terraform/gcp"
  local ws raw base_url
  need_cmd terraform gcloud
  log gcp "Checking GCP application-default login."
  if ! gcloud auth application-default print-access-token >/dev/null; then
    log gcp "GCP login failed. Run: gcloud auth application-default login"
    record "gcp" "-" "-" "error" "FAIL"
    return 0
  fi
  ws="$(workspace_for "$ENV_NAME")"
  TOUCHED_GCP=1
  if ! raw="$(use_workspace "$dir" "$ws" "gcp" && terraform -chdir="$dir" output -raw site_url)"; then
    log gcp "Could not read site_url from workspace ${ws}."
    record "gcp" "-" "-" "error" "FAIL"
    return 0
  fi
  if [[ -z "$raw" ]]; then
    log gcp "site_url from workspace ${ws} is empty."
    record "gcp" "-" "-" "error" "FAIL"
    return 0
  fi
  base_url="${raw%/index.html}"
  check_provider_files "gcp" "$base_url"
}

validate_cloudflare() {
  local base_url
  if [[ "$ENV_NAME" == "prod" ]]; then
    base_url="https://${CLOUDFLARE_PROJECT_NAME}.pages.dev"
  else
    base_url="https://develop.${CLOUDFLARE_PROJECT_NAME}.pages.dev"
  fi
  check_provider_files "cloudflare" "$base_url"
}

print_summary() {
  local provider file status content result shown
  echo
  printf '%-12s %-12s %-7s %-8s %s\n' "PROVIDER" "FILE" "STATUS" "CONTENT" "RESULT"
  while IFS='|' read -r provider file status content result; do
    if [[ -z "${provider}" ]]; then
      continue
    fi
    if [[ "$result" == "PASS" ]]; then
      shown="${C_GREEN}PASS${C_RESET}"
    else
      shown="${C_RED}FAIL${C_RESET}"
    fi
    printf '%-12s %-12s %-7s %-8s %s\n' "$provider" "$file" "$status" "$content" "$shown"
  done <"$RESULTS"
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
    require_var CLOUDFLARE_PROJECT_NAME
    ;;
  all)
    require_var AWS_PROFILE AWS_REGION GCP_PROJECT_ID CLOUDFLARE_PROJECT_NAME
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

need_cmd curl
if ! command -v shasum >/dev/null 2>&1 && ! command -v sha256sum >/dev/null 2>&1; then
  echo "Missing command: shasum or sha256sum"
  exit 1
fi

WORKDIR="$(mktemp -d)"
RESULTS="${WORKDIR}/results"
trap cleanup EXIT
touch "$RESULTS"

case "$TARGET" in
  aws) validate_aws ;;
  gcp) validate_gcp ;;
  cloudflare) validate_cloudflare ;;
  all)
    validate_aws
    validate_gcp
    validate_cloudflare
    ;;
esac

print_summary

if [[ "$FAILURES" -ne 0 ]]; then
  exit 1
fi
exit 0
