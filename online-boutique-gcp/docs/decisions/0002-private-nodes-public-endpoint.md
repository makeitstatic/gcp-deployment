---
title: ADR 0002 — Private nodes with a guarded public control-plane endpoint
tags:
  - adr
---

# ADR 0002 — Private nodes with a guarded public control-plane endpoint

- **Status:** Accepted
- **Date:** 2026-08-03
- **Deciders:** Platform engineering

## Context

Least privilege applies to network reachability as much as to IAM. Two separate exposure questions get conflated routinely, and they have different answers:

1. **Can anything reach the workloads directly?** This should be no, with one deliberate exception.
2. **Can an operator reach the Kubernetes API?** This must be yes, from somewhere.

The environment is reviewed by a panel who need to reproduce it from arbitrary networks, and one of the stated [assumptions](../01-context.md#assumptions) is that a reviewer's source address is not known in advance.

## Decision

- **Nodes are private:** `enable_private_nodes = true`, no external IPs on any node.
- **Egress is NAT-only:** Cloud Router plus Cloud NAT, with Private Google Access on the subnet so Google API traffic never leaves Google's network.
- **The control-plane endpoint stays public** (`enable_private_endpoint = false`) but is filtered by `master_authorized_networks`, currently `0.0.0.0/0` with the demo intent recorded in the variable's description.
- **Inbound to workloads exists only where explicitly created** — the `frontend-external` LoadBalancer Service.

## Consequences

**Positive**

- No workload is directly reachable from the internet. The attack surface is one load balancer, deliberately created.
- Image pulls and telemetry travel over Private Google Access rather than the public internet.
- Egress is centralised through NAT, so it is observable in one place and could later be filtered in one place.
- A reviewer can clone, apply and `kubectl` from anywhere with no bastion, which keeps the demo reproducible.

**Negative**

- **`0.0.0.0/0` on the control plane is exposure that exists purely for demo convenience.** Access is still gated by IAM — an unauthenticated caller gets nothing — but the endpoint is discoverable and reachable, which is strictly worse than not being. This is recorded as [gap 2](../03-security.md#known-gaps) and item 2 on the [roadmap](../06-roadmap.md#2-lock-the-control-plane-down).
- Cloud NAT is a fixed monthly cost that accrues whether or not anyone is using the environment — roughly a fifth of the idle bill ([05-cost](../05-cost.md#estimated-monthly-bill)).
- NAT port exhaustion becomes a cluster-wide egress failure mode ([02-architecture](../02-architecture.md#failure-modes)).

## Alternatives considered

**Fully private endpoint with a bastion host.** The stronger posture, and the production answer. Rejected for this deliverable because it requires either a bastion VM (another machine to patch, and a standing credential target) or IAP tunnelling configuration, both of which add reviewer friction for no gain in what is being demonstrated.

**Private endpoint plus Connect Gateway.** The best production option — no bastion, IAM-mediated, works from anywhere. Rejected only because it is more moving parts than a demo justifies. This is the recommended path forward.

**Restricting `master_authorized_networks` to a known CIDR.** Correct in any real engagement, and supported today by passing the variable — the runbook [shows the command](../04-runbook.md#deploy). Not the default only because the reviewer's address is unknown.

**Public nodes.** Simpler, and rejected immediately: it trades a large permanent increase in attack surface for a small reduction in setup complexity.
