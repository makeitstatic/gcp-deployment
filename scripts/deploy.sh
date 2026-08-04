#!/usr/bin/env bash
# Stands in for the CD stage of a pipeline: applies the Online Boutique
# manifests to the cluster and checks the shop answers.
#
# Usage: ./scripts/deploy.sh <PROJECT_ID> [CLUSTER_NAME] [REGION]

set -o errexit
set -o nounset
set -o pipefail

PROJECT_ID="${1:?Usage: deploy.sh <PROJECT_ID> [CLUSTER_NAME] [REGION]}"
CLUSTER_NAME="${2:-online-boutique}"
REGION="${3:-europe-west4}"
NAMESPACE="boutique"

# Pinned to a release tag rather than a branch, so this deploys the same
# objects next month as it does today. See ADR 0007.
#   MANIFEST_VERSION=v0.11.0 ./scripts/deploy.sh <PROJECT_ID>
MANIFEST_VERSION="${MANIFEST_VERSION:-v0.10.6}"
MANIFEST_URL="https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/${MANIFEST_VERSION}/release/kubernetes-manifests.yaml"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

log "Authenticating to cluster ${CLUSTER_NAME} (${REGION})"
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}"

log "Ensuring namespace '${NAMESPACE}' exists"
kubectl create namespace "${NAMESPACE}" \
  --dry-run=client \
  --output=yaml \
  | kubectl apply --filename=-

log "Applying Online Boutique manifests, pinned to ${MANIFEST_VERSION}"
kubectl apply \
  --namespace="${NAMESPACE}" \
  --filename="${MANIFEST_URL}"

# The upstream loadgenerator hammers the frontend continuously. Autopilot bills
# per Pod, so it stays at zero unless asked for.
#   DEPLOY_LOADGENERATOR=true ./scripts/deploy.sh <PROJECT_ID>
DEPLOY_LOADGENERATOR="${DEPLOY_LOADGENERATOR:-false}"
if [[ "${DEPLOY_LOADGENERATOR}" != "true" ]]; then
  log "Scaling loadgenerator to 0 replicas"
  kubectl scale deployment loadgenerator \
    --namespace="${NAMESPACE}" \
    --replicas=0
fi

log "Waiting for all deployments to become available (max 10m)"
kubectl wait deployment \
  --namespace="${NAMESPACE}" \
  --for=condition=Available \
  --all \
  --timeout=600s

log "Resolving external endpoint"
for attempt in $(seq 1 60); do
  IP="$(kubectl get service frontend-external \
          --namespace="${NAMESPACE}" \
          --output=jsonpath='{.status.loadBalancer.ingress[0].ip}' \
          2>/dev/null || true)"
  [[ -n "${IP}" ]] && break
  sleep 5
done

if [[ -z "${IP:-}" ]]; then
  echo "ERROR: LoadBalancer IP was not assigned in time." >&2
  exit 1
fi

log "Smoke test"
curl \
  --fail \
  --silent \
  --show-error \
  --output /dev/null \
  --write-out "HTTP %{http_code} from http://${IP}\n" \
  "http://${IP}"

log "Online Boutique is live: http://${IP}"
