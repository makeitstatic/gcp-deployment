#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Cost hygiene: tear everything down after developing, re-apply a few hours
# before the presentation (per the challenge's free-tier advice).
#
# Order matters: delete Kubernetes LoadBalancer Services FIRST, otherwise the
# GCLB forwarding rules/target pools they created outside Terraform's
# knowledge will block VPC deletion.
#
# Usage: ./scripts/destroy.sh <PROJECT_ID> [CLUSTER_NAME] [REGION]
# ------------------------------------------------------------------------------

set -o errexit  # abort the script when any command exits non-zero
set -o nounset  # abort when an undefined variable is referenced
set -o pipefail # a pipeline fails if ANY command in it fails, not just the last

PROJECT_ID="${1:?Usage: destroy.sh <PROJECT_ID> [CLUSTER_NAME] [REGION]}"
CLUSTER_NAME="${2:-online-boutique}"
REGION="${3:-europe-west4}"

# Credentials fetch may fail if the cluster is already gone — that is an
# acceptable state for a destroy script, hence the explicit '|| true'.
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}" \
  2>/dev/null || true

kubectl delete namespace boutique \
  --ignore-not-found=true \
  --timeout=300s || true

terraform destroy \
  -var="project_id=${PROJECT_ID}" \
  -auto-approve
