#!/usr/bin/env bash
# Everything the runbook lists under Prerequisites, in order: tooling, auth,
# project, billing, ADC, bootstrap APIs, validate.
#
# Creates nothing in Google Cloud — the state bucket and the platform are
# terraform apply's job. Every step checks before it acts, so re-running is
# harmless.
#
# Usage: ./scripts/setup.sh <PROJECT_ID> <BILLING_ACCOUNT_ID>

set -o errexit
set -o nounset
set -o pipefail

PROJECT_ID="${1:?Usage: setup.sh <PROJECT_ID> <BILLING_ACCOUNT_ID>}"
BILLING_ACCOUNT="${2:?Usage: setup.sh <PROJECT_ID> <BILLING_ACCOUNT_ID>}"

# Resolved from the script's own location so it works from any directory.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
skip() { printf '    \033[2m%s\033[0m\n' "$*"; }

# --- 1. Tooling ---------------------------------------------------------------

# gke-gcloud-auth-plugin is the one people miss, and kubectl's failure without
# it does not name the missing binary.
log "Checking tooling"
missing=()
for binary in terraform gcloud kubectl gke-gcloud-auth-plugin; do
  command -v "${binary}" >/dev/null 2>&1 || missing+=("${binary}")
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: missing: ${missing[*]}" >&2
  echo "  sudo pacman -S terraform kubectl" >&2
  echo "  paru -S google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin" >&2
  exit 1
fi
# No version check here: versions.tf already declares >= 1.10 and init enforces it.
skip "terraform, gcloud, kubectl, gke-gcloud-auth-plugin present"

# --- 2. Authentication --------------------------------------------------------

log "Checking gcloud authentication"
ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
if [[ -z "${ACTIVE_ACCOUNT}" ]]; then
  echo "    No active account — opening a browser."
  gcloud auth login
else
  skip "Authenticated as ${ACTIVE_ACCOUNT}"
fi

# --- 3. Project ---------------------------------------------------------------

# Does not create the project: creation depends on org policy and quota that
# vary per account, so this reports the command to run instead of guessing.
log "Verifying project ${PROJECT_ID}"
if ! gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
  echo "ERROR: project '${PROJECT_ID}' does not exist or you cannot see it." >&2
  echo "  Create it with: gcloud projects create ${PROJECT_ID}" >&2
  exit 1
fi
gcloud config set project "${PROJECT_ID}" --quiet

# --- 4. Billing ---------------------------------------------------------------

# GKE, Cloud NAT and the load balancer all refuse to create without it, trial
# credits or not.
log "Checking billing"
if [[ "$(gcloud billing projects describe "${PROJECT_ID}" \
          --format='value(billingEnabled)' 2>/dev/null)" == "True" ]]; then
  skip "Billing already linked"
else
  gcloud billing projects link "${PROJECT_ID}" \
    --billing-account="${BILLING_ACCOUNT}"
fi

# --- 5. Application Default Credentials ---------------------------------------

# Different from gcloud auth login: that authenticates the CLI, this is what
# Terraform reads. Missing it is the most common first-apply failure.
log "Checking Application Default Credentials"
if gcloud auth application-default print-access-token >/dev/null 2>&1; then
  skip "ADC present"
else
  echo "    No ADC — opening a browser."
  gcloud auth application-default login
fi
gcloud auth application-default set-quota-project "${PROJECT_ID}" --quiet

# --- 6. Bootstrap APIs --------------------------------------------------------

# main.tf enables the rest in code, but Terraform needs Service Usage on before
# it can make those calls.
log "Enabling bootstrap APIs"
gcloud services enable \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project="${PROJECT_ID}"

# --- 7. Validate --------------------------------------------------------------

# -backend=false works before the state bucket exists, which is the point: a
# schema error shows up now instead of eight minutes into a cluster create.
log "Validating Terraform"
(cd "${REPO_ROOT}/bootstrap" && terraform init -backend=false >/dev/null && terraform validate)
(cd "${REPO_ROOT}" && terraform init -backend=false >/dev/null && terraform fmt -check -recursive && terraform validate)

log "Prerequisites complete. Next:"
cat <<NEXT
    cd ${REPO_ROOT}/bootstrap
    terraform init && terraform apply -var="project_id=${PROJECT_ID}"
    cd ..
    sed "s/YOUR_PROJECT_ID/${PROJECT_ID}/" backend.hcl.example > backend.hcl
    terraform init -backend-config=backend.hcl
    terraform apply -var="project_id=${PROJECT_ID}"
    ./scripts/deploy.sh ${PROJECT_ID}
NEXT
