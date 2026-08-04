#!/usr/bin/env bash
# Shared helpers for the numbered stage scripts. Source it, do not run it:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# Shell options are deliberately NOT set here. A sourced file that quietly
# changes its caller's failure semantics is surprising, and someone opening a
# single stage should see how it fails without chasing another file.

# Resolved from this file's own location, so stages work from any directory.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Defaults shared by every stage. One copy, because three scripts each holding
# their own cluster name is how they drift apart. These must match the defaults
# in variables.tf — if you change one, change both.
DEFAULT_CLUSTER_NAME="gcp-deploy"
DEFAULT_REGION="europe-west4"
NAMESPACE="boutique"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
skip() { printf '    \033[2m%s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# require_cmd <binary>...
# Fails with every missing name at once, rather than one per run.
require_cmd() {
  local missing=()
  local binary
  for binary in "$@"; do
    command -v "${binary}" >/dev/null 2>&1 || missing+=("${binary}")
  done
  [[ ${#missing[@]} -eq 0 ]] || die "missing required commands: ${missing[*]}"
}

# require_arg <NAME> <value> [hint]
require_arg() {
  local name="$1"
  local value="${2:-}"
  local hint="${3:-}"
  [[ -n "${value}" ]] || die "${name} is required. ${hint}"
}
