---
title: Cost model
tags:
  - gcp
  - cost
  - finops
---

# Cost model

What this environment bills for, computed from the manifest that is actually deployed rather than estimated by feel — and where the numbers would change with a production budget.

> [!warning] Rates are indicative, the arithmetic is not
> List prices move and vary by region. Every figure below shows its working, so substitute the current `europe-west4` rate from the [pricing calculator](https://cloud.google.com/products/calculator) and the conclusion still holds. The *shape* of the bill — which line items dominate, and which are fixed versus variable — is what this document is for.
>
> For actuals rather than estimates: *Billing → Reports*, grouped by SKU.

## What Autopilot actually charges for

Autopilot bills per **Pod resource request**, not per node — that is the cost argument for it ([ADR 0001](decisions/0001-gke-autopilot.md)). It also enforces per-Pod minimums and rounds requests up, so the manifest's numbers are a floor you do not get to keep.

Summed from the pinned `v0.10.6` manifest, with `loadgenerator` at zero replicas:

| Deployment | CPU request | Memory request |
|---|---:|---:|
| `adservice` | 200m | 180 Mi |
| `cartservice` | 200m | 64 Mi |
| `checkoutservice` | 100m | 64 Mi |
| `currencyservice` | 100m | 64 Mi |
| `emailservice` | 100m | 64 Mi |
| `frontend` | 100m | 64 Mi |
| `paymentservice` | 100m | 64 Mi |
| `productcatalogservice` | 100m | 64 Mi |
| `recommendationservice` | 100m | 220 Mi |
| `redis-cart` | 70m | 200 Mi |
| `shippingservice` | 100m | 64 Mi |
| **As requested** | **1.27 vCPU** | **1.09 GiB** |
| **As billed** (250m / 512Mi per-Pod minimums) | **2.75 vCPU** | **5.50 GiB** |

**Autopilot bills 2.2× the CPU and 5.1× the memory these manifests ask for.** Eleven small services each request far less than the platform's minimum, and each one is rounded up individually. That is the single most useful cost fact about this deployment, and it is invisible unless you go looking — the manifest says 1.09 GiB and the invoice reflects 5.5.

The lesson generalises: on Autopilot, *many tiny Pods* is an anti-pattern. Consolidation, or accepting a larger request you actually use, costs the same or less.

## Estimated monthly bill

At 730 hours, everything left running continuously — which you should not do.

| Line item | Billing basis | Indicative rate | Monthly |
|---|---|---|---:|
| Autopilot vCPU | 2.75 vCPU × 730 h | ~$0.0445 / vCPU-h | ~$89 |
| Autopilot memory | 5.50 GiB × 730 h | ~$0.0049 / GiB-h | ~$20 |
| Cluster management fee | 1 cluster × 730 h | ~$0.10 / h | ~$73 |
| Cloud NAT gateway | 1 gateway × 730 h | ~$0.044 / h | ~$32 |
| Cloud NAT data processing | egress volume | ~$0.045 / GiB | negligible here |
| Load balancer forwarding rule | 1 rule × 730 h | ~$0.025 / h | ~$18 |
| VPC flow logs | 50% sampled | per GiB ingested | pennies at this scale |
| GCS state bucket | kilobytes, versioned | per GiB-month | pennies |
| | | **Total** | **~$232** |

The free tier covers one cluster's management fee, taking it to roughly **$159/month** left running.

### The number that matters more

| Scenario | Cost |
|---|---|
| A four-hour demo session | **~$1.30** |
| Left running for a month | ~$159–232 |
| Infrastructure up, app deleted | ~$105/month (cluster fee + NAT; the LB goes with the namespace) |

Leaving it up for a month costs over a hundred times what actually demonstrating it costs. That asymmetry is the entire justification for [70-destroy.sh](../scripts/70-destroy.sh) and for treating teardown as part of the workflow rather than housekeeping.

## Cost controls already in the repository

| Control | Where | Saves |
|---|---|---|
| `loadgenerator` scaled to 0 by default | [50-deploy.sh](../scripts/50-deploy.sh) | 300m CPU / 256 Mi billed continuously — and it generates NAT-processed traffic |
| One-command teardown | [70-destroy.sh](../scripts/70-destroy.sh) | Everything except the state bucket |
| Flow logs sampled at 50% | [modules/network/main.tf](../modules/network/main.tf) | Half the log ingestion, same forensic value at this scale |
| NAT logging `ERRORS_ONLY` | [modules/network/main.tf](../modules/network/main.tf) | Logging every translation event would dwarf the signal |
| Autopilot over Standard | [modules/gke/main.tf](../modules/gke/main.tf) | No idle node capacity — you pay for Pods, not for headroom |

## Free tier now, premium in production

Several choices here are deliberately the budget variant of a control with a paid, production-grade counterpart. Being able to name both sides is the point.

| Area | This build | Production consideration | Why it matters |
|---|---|---|---|
| **Network service tier** | Premium (the GCP default) | **Premium, non-negotiable** — required for the global external ALB with an anycast IP | Standard tier means hot-potato routing and regional-only load balancing |
| **GKE edition** | Standard edition on Autopilot | **GKE Enterprise** for fleet management, Config Sync, Policy Controller, managed service mesh | Per-tenant namespaces × many tenants × policy enforcement is exactly what it is priced for |
| **DDoS / WAF** | None | **Cloud Armor**; evaluate Enterprise for bill protection during an attack | On per-request billing, a volumetric attack is also a *financial* attack |
| **Availability** | Regional cluster, no SLA on trial | Multi-region behind a global anycast IP; published per-tier SLOs | Free trial buys architectural HA, not a contractual one |
| **Support** | Community | **Standard → Enhanced → Premium**, scaled to revenue at risk | The first Sev-1 pays for a year of Enhanced |
| **Commitment pricing** | On-demand, torn down nightly | **Committed use discounts** once a steady-state profile exists | Commit to the floor, burst on demand |
| **Security tooling** | Least privilege, private nodes, BinAuthz off | **Security Command Center**, Artifact Analysis scanning, BinAuthz enforced | Free tier proves the design; paid tooling provides continuous evidence |
| **Log retention** | Defaults, 50% flow sampling | 13-month audit retention, sinks to BigQuery | Incident forensics and per-tenant billing both die without history |

> [!tip] Free tier constrains spend, not architecture
> Everything structural — private VPC-native cluster, the identity chain, remote state, GitOps-shaped delivery — is identical at both ends. What budget buys is contractual assurance, continuous evidence and scale economics. That also answers the usual follow-up: with real money, nothing changes about the design and a great deal changes about the guarantees around it.

## Trial-account fine print

Trial accounts carry reduced regional quotas and cannot claim SLAs. An `apply` that fails on quota is almost always regional `CPUS` or `IN_USE_ADDRESSES`, both visible under *IAM & Admin → Quotas* and both resolved by upgrading the account — credits remain usable afterwards.
