---
title: ADR 0006 — Binary Authorization wired but disabled by default
tags:
  - adr
---

# ADR 0006 — Binary Authorization wired but disabled by default

- **Status:** Accepted
- **Date:** 2026-08-03
- **Deciders:** Platform engineering

## Context

Binary Authorization is GKE's admission gate: only container images carrying a valid attestation are allowed to run. It is the control that turns "our CI signs what it builds" into an enforced property rather than a convention, and it is the natural terminus of a supply-chain story.

The obstacle is concrete. Online Boutique's published images are **unsigned** — Google publishes them to a public Artifact Registry without attestations. Enabling enforcement against them means every Pod is rejected at admission and the demo does not start.

Applying our own attestations is not available either: signing images we neither build nor own would be a fiction, and rebuilding them is an explicit [non-goal](../01-context.md#non-goals).

## Decision

Wire Binary Authorization behind a variable, `enable_binary_authorization`, defaulting to `false`. When true, the cluster is created with `evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"`.

Document both the reason for the default and the pipeline shape that flips it, in [06-roadmap](../06-roadmap.md#4-real-cicd-replacing-the-mock).

## Consequences

**Positive**

- The integration point is visible in code. A reviewer can see exactly where the delivery gate attaches, rather than being told it would go "somewhere in CI".
- Turning it on is a one-variable change once images are signed — no re-architecture.
- The reason for the default is recorded, so it reads as a constraint rather than an omission.

**Negative**

- **The control is not in force.** Anything with cluster write access can deploy any image from anywhere. This is [gap 3](../03-security.md#known-gaps), and it is real: a wired-but-disabled control provides no security whatsoever.
- A `dynamic` block that is empty by default is untested in the default path. The enabled path has not been exercised against a signed image here.
- There is a temptation to treat "we have BinAuthz" as a claim. It is not one, and this record exists partly to prevent that.

## Alternatives considered

**Enable it and accept a broken demo.** Rejected: the deliverable must run.

**Enable it with a policy allowing everything.** The worst option. It produces a cluster that reports Binary Authorization as enabled while admitting any image — a control that exists only to look good on an audit. Rejected on principle: a disabled control is honest, a permissive one is misleading.

**Rebuild the upstream images and sign them.** Would make enforcement genuine, and would mean forking and maintaining eleven applications to demonstrate one platform control. Rejected as disproportionate, and as modifying the application.

**Omit it entirely.** Simpler, and rejected because where the delivery gate attaches is exactly the kind of thing this repository is meant to show.
