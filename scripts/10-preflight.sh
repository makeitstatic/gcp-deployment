#!/usr/bin/env bash
# Stage 10 — local checks.
#
# No credentials, no project, no billing, nothing created. This runs the moment
# someone clones, so a broken checkout is caught in seconds rather than eight
# minutes into a cluster create.
#
# Usage: ./scripts/10-preflight.sh

set -o errexit
set -o nounset
set -o pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Checking tooling"
# gke-gcloud-auth-plugin is the one people miss, and kubectl's failure without it
# does not name the missing binary.
require_cmd terraform gcloud kubectl gke-gcloud-auth-plugin
# No version check here: versions.tf declares >= 1.10 and init enforces it.
skip "terraform, gcloud, kubectl, gke-gcloud-auth-plugin present"

log "Checking formatting"
terraform -chdir="${REPO_ROOT}" fmt -check -recursive

# -backend=false works before the state bucket exists, which is the point.
# bootstrap/ and the root resolve providers independently, so both are checked.
log "Validating bootstrap/"
terraform -chdir="${REPO_ROOT}/bootstrap" init -backend=false -input=false >/dev/null
terraform -chdir="${REPO_ROOT}/bootstrap" validate

log "Validating root module"
terraform -chdir="${REPO_ROOT}" init -backend=false -input=false >/dev/null
terraform -chdir="${REPO_ROOT}" validate

log "Preflight passed. Next: ./scripts/20-bootstrap.sh <PROJECT_ID> <BILLING_ACCOUNT_ID>"
