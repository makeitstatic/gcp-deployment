#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Mock CI/CD pipeline — "CD stage" for Online Boutique.
#
# The challenge allows mocking the pipeline with a bash deployment of the
# upstream Kubernetes manifests. This script is written the way a real CD
# job would be: idempotent, fail-fast, no interactive prompts, explicit
# health verification, and it prints the URL a reviewer needs.
#
# Style note: long-form option names are used throughout (--namespace instead
# of -n, --filename instead of -f, set -o errexit instead of set -e). In a
# script that gets code-reviewed, self-documenting flags beat brevity.
#
# Real-world evolution (talking point, matches Part-1 design):
#   Git push -> Cloud Build (build, unit tests, Trivy scan, image signing)
#            -> Artifact Registry -> Binary Authorization attestation
#            -> Argo CD syncs the environment repo (GitOps pull model)
# This script stands in for the final sync step only.
#
# Usage:
#   ./scripts/deploy.sh <PROJECT_ID> [CLUSTER_NAME] [REGION]
# ------------------------------------------------------------------------------

# Fail-fast semantics, spelled out:
set -o errexit  # abort the script when any command exits non-zero
set -o nounset  # abort when an undefined variable is referenced
set -o pipefail # a pipeline fails if ANY command in it fails, not just the last

PROJECT_ID="${1:?Usage: deploy.sh <PROJECT_ID> [CLUSTER_NAME] [REGION]}"
CLUSTER_NAME="${2:-online-boutique}"
REGION="${3:-europe-west4}"
NAMESPACE="boutique"

# Pin the upstream manifests to a release tag, never a branch. Resolving
# 'master' means the same command deploys different images next month —
# the demo changes under you, and a failure can't be reproduced against the
# artefact that caused it. Immutable ref = repeatable deploy, which is the
# whole reason this script is shaped like a CD job.
#
# To evaluate a newer upstream release:
#   MANIFEST_VERSION=v0.11.0 ./scripts/deploy.sh <PROJECT_ID>
MANIFEST_VERSION="${MANIFEST_VERSION:-v0.10.6}"
MANIFEST_URL="https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/${MANIFEST_VERSION}/release/kubernetes-manifests.yaml"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

log "Authenticating to cluster ${CLUSTER_NAME} (${REGION})"
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}"

log "Ensuring namespace '${NAMESPACE}' exists (workloads never run in 'default')"
kubectl create namespace "${NAMESPACE}" \
  --dry-run=client \
  --output=yaml \
  | kubectl apply --filename=-

log "Applying Online Boutique manifests, pinned to ${MANIFEST_VERSION}"
# 'kubectl apply' is declarative & idempotent — safe to re-run, which is the
# property a CD job needs.
kubectl apply \
  --namespace="${NAMESPACE}" \
  --filename="${MANIFEST_URL}"

# --- Free-tier cost control ---------------------------------------------------
# The upstream manifest includes 'loadgenerator', a Locust pod that hammers
# the frontend continuously. Great for demoing autoscaling, but on Autopilot
# you pay per Pod request — so on a free-tier/credits account it silently
# burns budget 24/7. Default: scale it to zero. Re-enable for the live demo:
#   DEPLOY_LOADGENERATOR=true ./scripts/deploy.sh <PROJECT_ID>
DEPLOY_LOADGENERATOR="${DEPLOY_LOADGENERATOR:-false}"
if [[ "${DEPLOY_LOADGENERATOR}" != "true" ]]; then
  log "Scaling loadgenerator to 0 replicas (free-tier cost control)"
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
# The upstream manifest exposes the frontend via a Service of type
# LoadBalancer ('frontend-external'). Fine for a demo; the production path is
# a Gateway/Ingress behind the Global ALB + Cloud Armor (front-door-first).
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
