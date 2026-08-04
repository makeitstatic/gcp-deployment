#!/usr/bin/env bash
# Stage 30 — write a reviewable plan.
#
# Separate from stage 40 deliberately. Bare `terraform apply` prints a plan and
# waits for yes, but it re-plans when you confirm, so what executes is not
# strictly what you read. A saved plan is also the only artefact here that can
# be attached to a pull request and read by someone who is not at the keyboard.
# Until CI provides a gate, this is the gate. See ADR 0008.
#
# Usage: ./scripts/30-plan.sh <PROJECT_ID>

set -o errexit
set -o nounset
set -o pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PROJECT_ID="${1:-}"
require_arg PROJECT_ID "${PROJECT_ID}" "Usage: 30-plan.sh <PROJECT_ID>"
require_cmd terraform

TFPLAN="${TFPLAN:-tfplan}"

log "Planning against project ${PROJECT_ID}"
terraform -chdir="${REPO_ROOT}" plan \
  -input=false \
  -out="${TFPLAN}" \
  -var="project_id=${PROJECT_ID}"

log "Plan written to ${REPO_ROOT}/${TFPLAN} — read it, then run ./scripts/40-apply.sh"
