---
title: Context, requirements and scope
tags:
  - gcp
  - architecture
---

# Context, requirements and scope

What was asked for, what was deliberately left out, and what the rest of these documents assume. Read this first — every later decision is justified against the constraints recorded here.

## The brief

Stand up an empty Google Cloud project into a private, least-privilege Kubernetes environment, entirely through infrastructure as code, and deploy Google's [Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo) demo application onto it through something shaped like a delivery pipeline. The work is reviewed by a panel, so the reasoning behind each choice is part of the deliverable rather than an appendix to it.

## Mandatory requirements

Each maps to a specific resource, so compliance is verifiable in code rather than asserted in prose.

| # | Requirement | Where it lives | How |
|---|---|---|---|
| R1 | Nodes on `10.0.0.0/16` | [modules/network/main.tf](../modules/network/main.tf) | Primary range of the GKE subnet |
| R2 | Pods on `10.1.0.0/16` | [modules/network](../modules/network/main.tf) → [modules/gke](../modules/gke/main.tf) | Secondary range `pods`, bound via `ip_allocation_policy` |
| R3 | Services on `10.2.0.0/16` | same | Secondary range `services`, bound via `ip_allocation_policy` |
| R4 | Least privilege throughout | [modules/gke/main.tf](../modules/gke/main.tf) | Dedicated node service account replacing the Compute default; private nodes; NAT-only egress; authorized networks; Shielded nodes and no privileged Pods enforced by Autopilot |
| R5 | Engineers collaborate without side effects | [bootstrap/](../bootstrap/main.tf), [versions.tf](../versions.tf), [.gitignore](../.gitignore) | Versioned remote state with native locking; pinned providers; modules as ownership boundaries; APIs enabled in code |
| R6 | Application deployed via a pipeline | [scripts/deploy.sh](../scripts/deploy.sh) | Mock CD job: fail-fast, idempotent, health-gated, smoke-tested, pinned to a release tag |

## Non-goals

Stated explicitly, because the fastest way to misread this repository is to measure it against a target it was never aiming at.

- **Multi-region or multi-cluster.** One regional cluster in `europe-west4`. Regional gives zone-level resilience; anything beyond that is a cost and complexity decision nobody has made yet.
- **Multi-tenancy.** Per-tenant namespaces are the direction of travel, but nothing here implements tenant isolation, quotas or per-tenant policy.
- **Production-grade delivery.** [deploy.sh](../scripts/deploy.sh) is deliberately a stand-in for the final sync step of a real pipeline. There is no build, no test stage, no image signing, no GitOps controller. See [ADR 0007](decisions/0007-pin-manifests-to-release-tag.md) and [06-roadmap](06-roadmap.md).
- **Modifying the application.** The upstream manifests are applied as published. No forks, no patches, no re-images — so the repository is about the platform, not the app.
- **Persistent application data.** `redis-cart` uses an `emptyDir`. Carts do not survive a Pod restart, and that is upstream's design, not an oversight here.
- **Cost optimisation beyond the structural.** Autopilot's per-Pod billing and a zero-replica load generator are in scope; committed-use discounts and workload right-sizing are not, because there is no steady-state load profile to right-size against.
- **A service mesh.** Online Boutique speaks gRPC service-to-service without one. Istio or Cloud Service Mesh would add mTLS and traffic policy, and would also add a control plane nobody asked for.

## Assumptions

Challenge these first — if one is wrong, the conclusion downstream of it is probably wrong too.

1. **One project, one environment.** Environment separation would be a `envs/` layer over the same modules, not a change to them.
2. **The reviewer can reach the control plane from an arbitrary address.** This is what justifies `0.0.0.0/0` in the authorized networks, and it is the assumption most worth revisiting first. See [ADR 0002](decisions/0002-private-nodes-public-endpoint.md).
3. **Upstream images are unsigned and stay that way.** Binary Authorization is therefore a demonstrated capability rather than an enforced control. See [ADR 0006](decisions/0006-binary-authorization-off-by-default.md).
4. **The account is a free trial or credit-backed.** This shapes teardown discipline and quota expectations, not the architecture. See [05-cost](05-cost.md).
5. **No compliance regime applies.** No data residency, audit retention or sovereignty requirement has been stated. Several choices — log retention in particular — would change if one had been.

## Constraints

| Constraint | Consequence |
|---|---|
| Mandated /16 ranges | Wildly oversized for the workload, and implemented as specified. The disagreement is recorded in [ADR 0005](decisions/0005-mandated-cidr-sizing.md) rather than silently corrected. |
| Free-trial quotas | Regional CPU and in-use IP address quotas are lower than on a paid account; an `apply` that fails usually fails on one of these. |
| Unsigned upstream images | Admission control can be wired but not enforced. |
| Reviewed by reading, not just running | Structure, comments and decision records carry as much weight as the resources they create. |

## What "done" looks like

The environment is correct when all five hold, each checkable by a command in [04-runbook](04-runbook.md#proving-it-works):

1. The three mandated ranges exist and are *bound to the cluster*, not merely present in the VPC.
2. No node has an external IP, and egress leaves through Cloud NAT.
3. Nodes run as a dedicated service account, not the Compute Engine default.
4. A second concurrent `terraform apply` blocks rather than corrupting state.
5. The frontend answers HTTP 200 on a load balancer address, with every Deployment reporting `Available`.
