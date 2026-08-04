#!/usr/bin/env bash
# Stage 20 — prepare the Google Cloud project and the Terraform state backend.
#
# Every step checks before it acts, so re-running is a no-op rather than an
# error. The only thing created is the state bucket: pennies a month, protected
# by prevent_destroy, and the prerequisite for every stage after this one.
#
# Everything expensive happens in stages 30 and 40, behind the plan gate.
#
# Usage: ./scripts/20-bootstrap.sh <PROJECT_ID> <BILLING_ACCOUNT_ID>

set -o errexit
set -o nounset
set -o pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PROJECT_ID="${1:-}"
BILLING_ACCOUNT="${2:-}"
require_arg PROJECT_ID "${PROJECT_ID}" "Usage: 20-bootstrap.sh <PROJECT_ID> <BILLING_ACCOUNT_ID>"
require_arg BILLING_ACCOUNT "${BILLING_ACCOUNT}" "Find it with: gcloud billing accounts list"

require_cmd terraform gcloud

# --- Authentication -----------------------------------------------------------

log "Checking gcloud authentication"
ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
if [[ -z "${ACTIVE_ACCOUNT}" ]]; then
  echo "    No active account — opening a browser."
  gcloud auth login
else
  skip "Authenticated as ${ACTIVE_ACCOUNT}"
fi

# --- Project ------------------------------------------------------------------

# Does not create the project: creation depends on org policy, folder placement
# and quota that vary per account, so this reports the command instead of guessing.
log "Verifying project ${PROJECT_ID}"
gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1 \
  || die "project '${PROJECT_ID}' does not exist or you cannot see it. Create it with: gcloud projects create ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}" --quiet

# --- Billing ------------------------------------------------------------------

# GKE, Cloud NAT and the load balancer all refuse to create without it, trial
# credits or not.
log "Checking billing"
if [[ "$(gcloud billing projects describe "${PROJECT_ID}" \
          --format='value(billingEnabled)' 2>/dev/null)" == "True" ]]; then
  skip "Billing already linked"
else
  gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT}"
fi

# --- Application Default Credentials ------------------------------------------

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

# --- Bootstrap APIs -----------------------------------------------------------

# main.tf enables the rest in code, but Terraform needs Service Usage on before
# it can make those calls.
log "Enabling bootstrap APIs"
gcloud services enable \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project="${PROJECT_ID}"

# --- State bucket -------------------------------------------------------------

# A backend cannot create its own bucket, so bootstrap/ runs with local state.
# -auto-approve here rather than the plan gate of stages 30 and 40: this module
# creates one bucket and its plan is four lines. See ADR 0008.
log "Creating the Terraform state bucket"
terraform -chdir="${REPO_ROOT}/bootstrap" init -input=false
terraform -chdir="${REPO_ROOT}/bootstrap" apply \
  -input=false \
  -auto-approve \
  -var="project_id=${PROJECT_ID}"

# --- Point the root module at it ----------------------------------------------

# The bucket name is project-specific, so it is supplied at init rather than
# hardcoded in versions.tf. -reconfigure because stage 10 initialised the root
# with -backend=false.
log "Initialising the root module against the state bucket"
sed "s/YOUR_PROJECT_ID/${PROJECT_ID}/" "${REPO_ROOT}/backend.hcl.example" > "${REPO_ROOT}/backend.hcl"
terraform -chdir="${REPO_ROOT}" init \
  -input=false \
  -reconfigure \
  -backend-config="${REPO_ROOT}/backend.hcl"

log "Bootstrap complete. Next: ./scripts/30-plan.sh ${PROJECT_ID}"
