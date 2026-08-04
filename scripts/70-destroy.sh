#!/usr/bin/env bash
# Stage 70 — tear everything down.
#
# Cloud NAT and the load balancer bill while idle, so run this after every
# session. The namespace goes first: Kubernetes created load balancer forwarding
# rules that Terraform does not know about, and they block the VPC delete.
#
# The state bucket survives by design (prevent_destroy), so the next run resumes
# at stage 30 rather than stage 20.
#
# Usage: ./scripts/70-destroy.sh <PROJECT_ID> [CLUSTER_NAME] [REGION]

set -o errexit
set -o nounset
set -o pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PROJECT_ID="${1:-}"
require_arg PROJECT_ID "${PROJECT_ID}" "Usage: 70-destroy.sh <PROJECT_ID> [CLUSTER_NAME] [REGION]"
require_cmd terraform gcloud kubectl

CLUSTER_NAME="${2:-${DEFAULT_CLUSTER_NAME}}"
REGION="${3:-${DEFAULT_REGION}}"

# Both of these fail if the cluster is already gone, which is fine here. If the
# cluster exists but this step is skipped, the forwarding rules it leaves behind
# will block the VPC delete below — check the output rather than assuming.
log "Deleting namespace '${NAMESPACE}' so its load balancers go first"
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}" \
  2>/dev/null || true

kubectl delete namespace "${NAMESPACE}" \
  --ignore-not-found=true \
  --timeout=300s || true

log "Destroying the platform"
terraform -chdir="${REPO_ROOT}" destroy \
  -input=false \
  -var="project_id=${PROJECT_ID}" \
  -auto-approve

log "Done. The state bucket and the enabled APIs remain, both by design."
