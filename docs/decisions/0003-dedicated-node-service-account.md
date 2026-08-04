---
title: ADR 0003 — A dedicated node service account, not the Compute default
tags:
  - adr
---

# ADR 0003 — A dedicated node service account, not the Compute default

- **Status:** Accepted
- **Date:** 2026-08-03
- **Deciders:** Platform engineering

## Context

If no service account is specified, GKE nodes run as the **Compute Engine default service account**. On many projects that account carries `roles/editor`, because it is granted that by default when the Compute API is enabled and it is rarely trimmed afterwards.

The consequence is specific and severe: any process that achieves code execution in any Pod can reach the node's metadata server, obtain that account's token, and act as project Editor. One application vulnerability becomes near-total project compromise, with no further exploitation required.

This is the highest-severity default in a standard GKE deployment, and it is silent — nothing warns you, and the cluster works perfectly either way.

## Decision

Create a dedicated service account, `gcp-deploy-nodes@`, and bind exactly the five roles Google documents as the minimum for a functioning node:

| Role | Needed for |
|---|---|
| `roles/logging.logWriter` | Shipping node and Pod logs |
| `roles/monitoring.metricWriter` | Shipping metrics |
| `roles/monitoring.viewer` | The metrics agent reading back |
| `roles/artifactregistry.reader` | Pulling images |
| `roles/stackdriver.resourceMetadata.writer` | Resource metadata for observability |

Attach it to Autopilot's node provisioning via `cluster_autoscaling.auto_provisioning_defaults.service_account`, so nodes created on demand inherit it rather than falling back to the default.

Keep this strictly separate from **workload** identity: applications that need Google APIs get a Workload Identity binding between their Kubernetes ServiceAccount and a Google service account. Node credentials are never the mechanism by which an application authenticates, and no JSON key is ever exported.

## Consequences

**Positive**

- A compromised Pod inherits log-write, metric-write and image-pull. There is no path from there to project administration.
- The blast radius of the node identity is now small enough to state in one sentence, which is what makes it auditable.
- `terraform output node_service_account` makes the claim checkable in seconds ([04-runbook](../04-runbook.md#proving-it-works)).
- The two identity planes stay conceptually distinct, so nobody is tempted to "just add a role to the node SA" when an application needs an API.

**Negative**

- Any future node-level agent needing a further permission requires a deliberate role addition — which is the point, but it is friction.
- Five bindings are five things to keep correct; drift here is silent until something stops shipping telemetry.
- Autopilot's `auto_provisioning_defaults` is easy to omit. Creating the account without wiring it there produces a cluster that *looks* least-privilege while nodes still run as the default. The `depends_on` in [modules/gke/main.tf](../../modules/gke/main.tf) exists so the bindings land before the cluster does.

## Alternatives considered

**Use the Compute Engine default service account.** Zero effort, and the reason this misconfiguration is so widespread. Rejected — it is the specific failure this decision exists to prevent.

**Use the default account but strip `roles/editor` from it.** Better, but project-wide: it affects every resource that account backs, so the change is riskier than creating a purpose-built account, and it leaves a shared identity across unrelated workloads.

**Grant the node account nothing and rely on Workload Identity for everything.** Attractive in principle. Rejected because nodes genuinely need to pull images and ship their own telemetry before any workload identity exists — a cluster whose nodes cannot log is not observable.
