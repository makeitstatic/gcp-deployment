#!/usr/bin/env bash
# Stage 60 — prove the requirements hold.
#
# Every mandated requirement, asserted rather than claimed. Exits non-zero if
# any check fails, so an orchestrator can gate on it and a reviewer can run it
# themselves instead of taking the documentation's word.
#
# Reads only. Safe to run at any time once the app is deployed.
#
# Usage: ./scripts/60-verify.sh <PROJECT_ID> [CLUSTER_NAME] [REGION]

set -o errexit
set -o nounset
set -o pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PROJECT_ID="${1:-}"
require_arg PROJECT_ID "${PROJECT_ID}" "Usage: 60-verify.sh <PROJECT_ID> [CLUSTER_NAME] [REGION]"
require_cmd gcloud kubectl curl

CLUSTER_NAME="${2:-${DEFAULT_CLUSTER_NAME}}"
REGION="${3:-${DEFAULT_REGION}}"
SUBNET="${CLUSTER_NAME}-vpc-gke"

# Fetched once, up front: both the node checks and the application checks need
# it. If this fails nothing below can be verified, so it is fatal rather than a
# failed assertion.
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}" >/dev/null 2>&1 \
  || die "cannot reach cluster ${CLUSTER_NAME} in ${REGION}. Has stage 40 run?"

FAILURES=0

# Assertions must not abort the run on the first failure — the point is to
# report everything that is wrong in one pass, so each check captures its own
# command output and compares.
check() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  if [[ "${actual}" == "${expected}" ]]; then
    printf '    \033[32m PASS \033[0m %s\n' "${description}"
  else
    printf '    \033[31m FAIL \033[0m %s\n           expected: %s\n           actual:   %s\n' \
      "${description}" "${expected}" "${actual:-<empty>}"
    FAILURES=$((FAILURES + 1))
  fi
}

cluster_field() {
  gcloud container clusters describe "${CLUSTER_NAME}" \
    --region "${REGION}" \
    --project "${PROJECT_ID}" \
    --format="value($1)" 2>/dev/null || true
}

# describe does not accept --filter, so the ranges are fetched once as
# "<name>\t<cidr>" lines and matched here instead.
SECONDARY_RANGES="$(gcloud compute networks subnets describe "${SUBNET}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}" \
  --flatten='secondaryIpRanges[]' \
  --format='value(secondaryIpRanges.rangeName,secondaryIpRanges.ipCidrRange)' || true)"

secondary_range() {
  printf '%s\n' "${SECONDARY_RANGES}" | awk -v name="$1" '$1 == name { print $2 }'
}

# --- Networking (R1-R3) -------------------------------------------------------

log "Networking — the three mandated ranges"

check "Nodes on 10.0.0.0/16" "10.0.0.0/16" \
  "$(gcloud compute networks subnets describe "${SUBNET}" \
       --region "${REGION}" --project "${PROJECT_ID}" \
       --format='value(ipCidrRange)' 2>/dev/null || true)"

check "Pods on 10.1.0.0/16" "10.1.0.0/16" "$(secondary_range pods)"
check "Services on 10.2.0.0/16" "10.2.0.0/16" "$(secondary_range services)"

# Present on the subnet is not the same as bound to the cluster. This is what
# makes the cluster VPC-native rather than routes-based.
check "Pod range bound to the cluster" "pods" \
  "$(cluster_field 'ipAllocationPolicy.clusterSecondaryRangeName')"
check "Service range bound to the cluster" "services" \
  "$(cluster_field 'ipAllocationPolicy.servicesSecondaryRangeName')"

# --- Least privilege (R4) -----------------------------------------------------

log "Least privilege"

check "Nodes are private" "True" \
  "$(cluster_field 'privateClusterConfig.enablePrivateNodes')"

# The claim that matters. A created service account proves nothing; the cluster
# has to actually provision nodes with it. Omit the Autopilot wiring and this is
# where it shows. Read from the cluster config, which is always available —
# Autopilot does not necessarily surface its node VMs as listable instances.
check "Autopilot provisions nodes with the dedicated service account" \
  "${CLUSTER_NAME}-nodes@${PROJECT_ID}.iam.gserviceaccount.com" \
  "$(cluster_field 'autoscaling.autoprovisioningNodePoolDefaults.serviceAccount')"

# Autopilot does not surface its node VMs in this project's Compute inventory,
# so `gcloud compute instances list` returns nothing and cannot be used here —
# an empty list would satisfy "no external IP" vacuously. The Kubernetes API
# always knows. A private node has no ExternalIP address, so any output is a
# finding.
check "No node carries an external IP" "" \
  "$(kubectl get nodes \
       --output=jsonpath='{range .items[*]}{.status.addresses[?(@.type=="ExternalIP")].address}{"\n"}{end}' \
     2>/dev/null | tr -d '[:space:]' || true)"

# Guards the check above: with zero nodes it would pass on an empty result.
NODE_TOTAL="$(kubectl get nodes --no-headers 2>/dev/null | grep -c . || true)"
check "Cluster has running nodes" "true" \
  "$([[ "${NODE_TOTAL}" -gt 0 ]] && echo true || echo false)"

check "Node service account holds exactly 5 roles" "5" \
  "$(gcloud projects get-iam-policy "${PROJECT_ID}" \
       --flatten='bindings[].members' \
       --filter="bindings.members:${CLUSTER_NAME}-nodes@" \
       --format='value(bindings.role)' 2>/dev/null | grep -c . || true)"

# --- Ops (R5) -----------------------------------------------------------------

log "Ops"

check "State is remote, not local" "gcs" \
  "$(grep -oE 'backend "[a-z]+"' "${REPO_ROOT}/versions.tf" | grep -oE '"[a-z]+"' | tr -d '"' || true)"

check "Provider lock file is committed" "present" \
  "$([[ -f "${REPO_ROOT}/.terraform.lock.hcl" ]] && echo present || echo missing)"

# --- Application (R6) ---------------------------------------------------------

log "Application"

DEPLOY_TOTAL="$(kubectl get deployments --namespace "${NAMESPACE}" \
                  --no-headers 2>/dev/null | grep -c . || true)"
DEPLOY_READY="$(kubectl get deployments --namespace "${NAMESPACE}" \
                  --output=jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Available")].status}{"\n"}{end}' \
                  2>/dev/null | grep -c True || true)"
check "Every Deployment reports Available" "${DEPLOY_TOTAL}" "${DEPLOY_READY}"

check "Workloads are not in the default namespace" "0" \
  "$(kubectl get deployments --namespace default --no-headers 2>/dev/null | grep -c . || true)"

FRONTEND_IP="$(kubectl get service frontend-external \
                 --namespace "${NAMESPACE}" \
                 --output=jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
check "Frontend answers HTTP 200" "200" \
  "$(curl --silent --output /dev/null --max-time 10 \
       --write-out '%{http_code}' "http://${FRONTEND_IP}" 2>/dev/null || true)"

# --- Result -------------------------------------------------------------------

if [[ ${FAILURES} -gt 0 ]]; then
  die "${FAILURES} check(s) failed"
fi

log "All checks passed. Tear down when finished: ./scripts/70-destroy.sh ${PROJECT_ID}"
