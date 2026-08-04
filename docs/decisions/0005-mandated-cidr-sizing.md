---
title: ADR 0005 — Implement the mandated CIDR sizing, and record the disagreement
tags:
  - adr
---

# ADR 0005 — Implement the mandated CIDR sizing, and record the disagreement

- **Status:** Accepted
- **Date:** 2026-08-03
- **Deciders:** Platform engineering

## Context

The brief mandates three ranges: `10.0.0.0/16` for nodes, `10.1.0.0/16` for Pods, `10.2.0.0/16` for Services ([R1–R3](../01-context.md#mandatory-requirements)).

Two of the three are considerably larger than any plausible need:

- **Nodes: a /16 is 65,536 addresses.** This cluster will run single-digit nodes. A /22 (1,022 usable) would be generous.
- **Services: a /16 is 65,536 ClusterIPs.** The workload defines 12. A /20 would be lavish.
- **Pods: a /16 is defensible.** GKE allocates a /24 per node by default, so a /16 supports 256 nodes — the one range where the mandate is close to reasonable.

VPC address space is painful to reclaim: primary ranges cannot be shrunk in place, so correcting this later means a new subnet and a cluster migration. Oversized ranges also foreclose future peering options — an RFC1918 block consumed here is unavailable to anything that must peer without overlap.

## Decision

**Implement the mandated ranges exactly as specified.** Record the disagreement in [variables.tf](../../variables.tf), in this ADR, and in [02-architecture](../02-architecture.md#address-plan) — visible to anyone reading either the code or the documents, and impossible to mistake for an oversight.

## Consequences

**Positive**

- The brief is satisfied literally and verifiably. Compliance is checkable with one `gcloud` command ([04-runbook](../04-runbook.md#proving-it-works)).
- The reasoning is preserved at the point of use. A future engineer sees the disagreement in the variable definition, not only in a document they may never open.
- The ranges are variables with defaults, not literals, so right-sizing is a tfvars change rather than a refactor.

**Negative**

- Roughly 130,000 RFC1918 addresses are consumed to serve a workload needing a few hundred. In an organisation with an address-plan authority, this would be a rejected allocation request.
- Peering with any network already using `10.0.0.0/14` becomes impossible without renumbering one side.
- It bakes in a habit — "take a /16, it's fine" — that scales badly across many clusters.

## Alternatives considered

**Right-size them anyway and explain afterwards.** Produces a technically better network and fails the requirement as written. A reviewer checking compliance finds a mismatch and has to decide whether it was judgement or carelessness — and they cannot tell from the artefact. Rejected: silently substituting your own judgement for a stated requirement is the actual failure here, and it is worse than the oversized range.

**Implement as mandated and say nothing.** Rejected for the opposite reason. It reads as not having noticed, which is indistinguishable from not knowing.

**Split the difference — mandated for Pods, right-sized for nodes and Services.** Rejected as the worst of both: partial compliance, no clean story, and a reviewer still has to work out which parts were deliberate.

## Note

This is the pattern I would follow on any engagement: raise the concern once, in writing, with the reasoning and the cost of being wrong; then build what was agreed. The disagreement is documented, not litigated, and if the constraint was arbitrary the record makes it cheap to revisit later.
