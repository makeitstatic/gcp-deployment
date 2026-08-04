---
title: ADR 0004 — Versioned GCS remote state with native locking
tags:
  - adr
---

# ADR 0004 — Versioned GCS remote state with native locking

- **Status:** Accepted
- **Date:** 2026-08-03
- **Deciders:** Platform engineering

## Context

Requirement [R5](../01-context.md#mandatory-requirements) — "engineers collaborate without side effects" — is, underneath the phrasing, a **state** problem. With local state, three failures are inevitable rather than possible:

1. Two engineers apply concurrently; the second overwrites the first's state and the infrastructure no longer matches any record of it.
2. One engineer's laptop holds the only copy of the truth.
3. Different provider versions produce different plans from identical code.

A secondary problem: Terraform needs a backend bucket, but the bucket has to be created by something. Solving that inside the same root module is circular.

## Decision

A **separate `bootstrap/` root module**, run once with local state, creates the state bucket with:

- object **versioning** — state history and rollback
- **uniform bucket-level access** — IAM only, no per-object ACLs
- **public access prevention: enforced**
- **`prevent_destroy`** — Terraform refuses to delete it
- a lifecycle rule keeping the last 10 noncurrent versions

The root module then uses that bucket as a `gcs` backend with prefix `gcp-deploy/root`. The bucket *name* is supplied at init time via `-backend-config`, never hardcoded, because it is project-specific. Provider versions are pinned (`~> 6.0`) and `.terraform.lock.hcl` is committed.

## Consequences

**Positive**

- The GCS backend provides **native state locking** with no extra infrastructure. A second concurrent apply blocks instead of corrupting state — Terraform's DynamoDB-equivalent comes free on GCS.
- Versioning means a bad state push is recoverable rather than terminal.
- The bootstrap module's own local state becomes irrelevant immediately after the first run; `prevent_destroy` protects the bucket from the module that made it.
- Pinned providers plus a committed lockfile mean every engineer and CI runner resolves byte-identical binaries.
- A fresh clone converges with one `apply`, because API enablement is in code too.

**Negative**

- The bootstrap module is a second root module to understand, with its own state and its own lifecycle. [20-bootstrap.sh](../../scripts/20-bootstrap.sh) runs both Terraform steps as one command, so it is no longer a manual prerequisite, but it is still a second thing in the repository that a newcomer has to account for.
- A crashed apply leaves the lock held, and the next engineer sees `Error acquiring the state lock` with no obvious owner. Blocking is the safe failure, but it needs `force-unlock` and the judgement to know when that is safe.
- `backend.hcl` is gitignored, so it never travels with the repository. [20-bootstrap.sh](../../scripts/20-bootstrap.sh) regenerates it from `backend.hcl.example`, so nobody types a bucket name, but a fresh clone has no backend configuration until that stage has run.
- State still contains resource identifiers and any sensitive outputs. Bucket IAM is the only thing protecting it; there is no state encryption beyond Google-managed keys at rest.

## Alternatives considered

**Local state.** Rejected: fails requirement R5 outright.

**Terraform Cloud / HCP Terraform.** Adds plan-on-PR, policy checks, a run history and hosted state. The right answer at team scale and where I would go next. Rejected here as more moving parts and an external dependency than a single-project deliverable justifies.

**Atlantis.** Plan-on-PR without leaving your own infrastructure, at the cost of running and securing Atlantis itself. Same reasoning as above.

**A hand-created bucket via `gcloud`.** Simpler than a bootstrap module, and rejected because it puts a mandatory manual step outside code — precisely the clickops prerequisite this repository is trying not to have.
