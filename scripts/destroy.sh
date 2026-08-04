#!/usr/bin/env bash
# Tears everything down. Cloud NAT and the load balancer bill while idle, so
# run this after every session.
#
# The namespace goes first: Kubernetes created load balancer forwarding rules
# that Terraform does not know about, and they block the VPC delete.
#
# Usage: ./scripts/destroy.sh <PROJECT_ID> [CLUSTER_NAME] [REGION]

set -o errexit
set -o nounset
set -o pipefail

PROJECT_ID="${1:?Usage: destroy.sh <PROJECT_ID> [CLUSTER_NAME] [REGION]}"
CLUSTER_NAME="${2:-online-boutique}"
REGION="${3:-europe-west4}"

# Both of these fail if the cluster is already gone, which is fine here.
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
