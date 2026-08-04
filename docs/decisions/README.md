---
title: Architecture decision records
tags:
  - adr
---

# Architecture decision records

One file per decision, in [Michael Nygard's format](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions). Each records **what was decided, when, why, and what it cost** — including the alternatives that lost and the reason they lost.

## Index

| # | Decision | Status |
|---|---|---|
| [0001](0001-gke-autopilot.md) | GKE Autopilot as the compute platform | Accepted |
| [0002](0002-private-nodes-public-endpoint.md) | Private nodes with a guarded public control-plane endpoint | Accepted |
| [0003](0003-dedicated-node-service-account.md) | A dedicated node service account, not the Compute default | Accepted |
| [0004](0004-gcs-remote-state.md) | Versioned GCS remote state with native locking | Accepted |
| [0005](0005-mandated-cidr-sizing.md) | Implement the mandated CIDR sizing, and record the disagreement | Accepted |
| [0006](0006-binary-authorization-off-by-default.md) | Binary Authorization wired but disabled by default | Accepted |
| [0007](0007-pin-manifests-to-release-tag.md) | Pin upstream manifests to a release tag, not a branch | Accepted |
| [0008](0008-explicit-plan-gate.md) | An explicit saved-plan gate before apply | Accepted |

## Conventions

**Records are immutable once accepted.** A decision that gets reversed is not edited — a new record supersedes it, and the old one gains `Superseded by 00NN`. The value of an ADR is that it shows what was believed *at the time*; editing history destroys exactly the thing that makes it worth keeping.

**Statuses:** `Proposed` → `Accepted` → `Superseded by 00NN` (or `Deprecated` where nothing replaces it).

**One decision per record.** If a record needs the word "and" in its title, it is probably two records.

**Consequences include the negative ones.** A record listing only benefits is marketing. The negative consequences are the part a future reader actually needs, because they are what they will be living with.

**New records are numbered sequentially** and never renumbered, so links and references stay stable.
