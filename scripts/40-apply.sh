#!/usr/bin/env bash
# Stage 40 — apply exactly the plan stage 30 wrote.
#
# Takes no PROJECT_ID: the variables are baked into the plan file, which is the
# whole point. What runs is what was reviewed, or nothing runs.
#
# Usage: ./scripts/40-apply.sh

set -o errexit
set -o nounset
set -o pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd terraform

TFPLAN="${TFPLAN:-tfplan}"

[[ -f "${REPO_ROOT}/${TFPLAN}" ]] \
  || die "no ${TFPLAN} found. Run ./scripts/30-plan.sh <PROJECT_ID> first."

log "Applying the reviewed plan"
# Terraform refuses a stale plan if state moved since it was written. That is
# the gate working, not a failure — re-plan and read it again.
terraform -chdir="${REPO_ROOT}" apply -input=false "${TFPLAN}"

log "Platform up. Next: ./scripts/50-deploy.sh <PROJECT_ID>"
