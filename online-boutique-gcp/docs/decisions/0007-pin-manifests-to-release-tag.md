---
title: ADR 0007 — Pin upstream manifests to a release tag, not a branch
tags:
  - adr
---

# ADR 0007 — Pin upstream manifests to a release tag, not a branch

- **Status:** Accepted
- **Date:** 2026-08-03
- **Deciders:** Platform engineering

## Context

[deploy.sh](../scripts/deploy.sh) fetches Online Boutique's manifests from the upstream repository over HTTPS and applies them. It originally resolved `master`.

A deployment script that resolves a moving branch has no reproducibility. The same command, run twice a month apart, can deploy different images, different resource requests, even different objects — and nothing in the output says so. Two failures follow:

1. **A demo can break without any local change.** An upstream commit lands between rehearsal and presentation, and the thing you tested is not the thing that runs.
2. **A failure cannot be investigated against the artefact that caused it**, because that artefact is no longer identifiable.

This matters more here than it would elsewhere, because the script's entire purpose is to have the *shape* of a CD job. Non-reproducible delivery is the one property a CD job cannot be allowed to have.

## Decision

Resolve manifests from a release tag, defaulting to `v0.10.6`, overridable by environment variable:

```bash
MANIFEST_VERSION="${MANIFEST_VERSION:-v0.10.6}"
MANIFEST_URL="https://raw.githubusercontent.com/.../${MANIFEST_VERSION}/release/kubernetes-manifests.yaml"
```

Log the resolved version at apply time, so the deployed release appears in the job output.

## Consequences

**Positive**

- The same command produces the same cluster contents, indefinitely.
- The deployed version is recorded in the log, where an investigation would look for it.
- Evaluating a newer upstream release is one environment variable, and reverting is the same.
- Every count in these documents — 12 Deployments, 11 ServiceAccounts, the resource sums in [05-cost](../05-cost.md) — is now a statement about a specific artefact rather than about whatever upstream currently holds.

**Negative**

- Upstream fixes, including security fixes, no longer arrive automatically. Someone has to bump the pin, and nothing prompts them to. This trades silent drift for silent staleness, which is better only because it is visible when you look.
- The pin is a second thing to maintain alongside the Terraform provider versions.
- A mistyped tag fails at `kubectl apply` rather than at argument parsing — `set -o errexit` aborts the run, but the error names the URL rather than the mistake.

## Alternatives considered

**Track `master`.** Always current, never reproducible. Rejected for the reasons above.

**Vendor the manifests into this repository.** Full control and offline deploys, at the cost of owning a copy of eleven applications' Kubernetes configuration and hand-merging upstream changes. Reasonable for a product; disproportionate for a platform demonstration.

**Pin to a commit SHA.** Strictly more precise than a tag, since tags can in principle be moved. Rejected as marginal: this upstream publishes immutable release tags, and a SHA is meaningless to a human reader, whereas `v0.10.6` can be looked up.

**Add a preflight check that the URL returns 200 before touching the cluster.** Genuinely worthwhile and not yet done — it would turn a confusing mid-apply failure into a clear one-line error. Deferred, not rejected.
