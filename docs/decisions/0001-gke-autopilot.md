---
title: ADR 0001 — GKE Autopilot as the compute platform
tags:
  - adr
---

# ADR 0001 — GKE Autopilot as the compute platform

- **Status:** Accepted
- **Date:** 2026-08-03
- **Deciders:** Platform engineering

## Context

The brief requires a private, least-privilege Kubernetes environment running Online Boutique, built entirely as code, on an account backed by trial credits. Two forces pull hardest: *least privilege must be structural rather than a checklist*, and *resource utilisation should be optimised for cost*.

Online Boutique ships as first-class Kubernetes manifests — 12 Deployments, a gRPC mesh between them, and an in-cluster Redis. Nothing in it needs node-level agents, custom machine shapes, GPUs, or host access.

## Decision

Use **GKE Autopilot**, regional, on the REGULAR release channel.

## Consequences

**Positive**

- Billing is per Pod resource request, so there is no idle node capacity to pay for. Cost tracks what is actually asked for.
- Security posture is opinionated by default: no SSH to nodes, no privileged Pods, Shielded nodes always on, node patching handled by Google. Least privilege becomes a property of the platform rather than a thing we remember to configure.
- Node pool sizing, bin-packing and upgrades stop being our problem, which is the largest single reduction in operational surface available.
- Workload Identity is enabled by default, so the workload identity plane exists without extra work ([03-security](../03-security.md#identity-two-planes)).

**Negative**

- Per-Pod minimums (250m CPU / 512 MiB) are enforced and applied *per Pod*. With eleven small services this bills 2.2× the CPU and 5.1× the memory the manifests request — quantified in [05-cost](../05-cost.md#what-autopilot-actually-charges-for). Many-small-Pods is an anti-pattern here.
- No DaemonSets requiring host access, no privileged sidecars, no custom kernel parameters. If a future requirement needs any of these, the escape hatch is a migration, not a flag.
- Pods can sit `Pending` while Autopilot provisions capacity — burst latency is the trade for not managing node pools.
- Less control over node placement and machine families than Standard.

## Alternatives considered

**GKE Standard.** More knobs: custom node pools, DaemonSet freedom, unusual GPU configurations, precise machine-type control. Rejected because nothing in the workload requires them and every one of those knobs is also a way to weaken the security posture by accident. It remains the escape hatch if node-level agents become a requirement.

**Cloud Run.** Lower operational overhead still, and attractive for stateless HTTP services. Rejected because the application is distributed as Kubernetes manifests with a gRPC service mesh and an in-cluster Redis; porting it would mean modifying the application, which is an explicit [non-goal](../01-context.md#non-goals). It would also diverge from a per-tenant-namespace direction of travel.

**Compute Engine managed instance groups.** Rejected outright: lift-and-shift would relocate the VM-sprawl problem rather than escape it, and would put node patching, image building and OS hardening back on us — the opposite of the least-privilege objective.
