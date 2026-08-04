---
title: ADR 0008 — An explicit saved-plan gate before apply
tags:
  - adr
---

# ADR 0008 — An explicit saved-plan gate before apply

- **Status:** Accepted
- **Date:** 2026-08-04
- **Deciders:** Platform engineering

## Context

Nothing in this repository gates an infrastructure change. [50-deploy.sh](../../scripts/50-deploy.sh) stands in for the CD stage of a pipeline, but there is no pipeline, so there is no plan-on-PR, no approval step and no second pair of eyes.

Bare `terraform apply` looks like it fills that gap. It prints a plan and waits for `yes`. Two things it does not do:

1. **It re-plans when you confirm.** What executes is generated after you finish reading, not the thing you read. State locking makes divergence unlikely, but unlikely is a different property from guaranteed.
2. **It produces nothing.** The plan exists on a terminal for as long as the scrollback lasts. It cannot be attached to a pull request or read by someone who is not at the keyboard, which is what review actually requires.

## Decision

The deploy path uses a saved plan:

```bash
terraform plan -out=tfplan -var="project_id=$PROJECT_ID"
terraform apply tfplan
```

`apply tfplan` executes that plan or fails. Both [04-runbook](../04-runbook.md#deploy) and the README quickstart use this form.

Two exemptions, both deliberate:

- **`bootstrap/`** creates one bucket. The plan is four lines and the ceremony adds nothing.
- **[70-destroy.sh](../../scripts/70-destroy.sh)** keeps `-auto-approve`. It is run repeatedly, and its safety comes from deleting the Kubernetes namespace before Terraform touches the VPC, not from a prompt.

## Consequences

**Positive**

- The applied change is the reviewed change, or the apply fails.
- The plan file is a reviewable artefact. It is the only thing this repository produces that can be examined *before* a change rather than after.
- It is the same shape as the gate that replaces it. When CI arrives ([06-roadmap](../06-roadmap.md#4-real-cicd-replacing-the-mock)), the human approval becomes a pipeline approval and the commands do not change.
- The exemptions are stated, so a reviewer reads them as decisions rather than inconsistency.

**Negative**

- Two commands where there was one, on every apply.
- Saved plans go stale. If state changes between plan and apply, Terraform refuses the file and the plan has to be regenerated and re-read. Correct behaviour, and still friction.
- Plan files can contain sensitive values. `tfplan` and `*.tfplan` are both gitignored, but a file that exists can be shared carelessly in a way that terminal output cannot.
- **It is a convention, not an enforcement.** Nothing prevents anyone running bare `apply`. Only a pipeline that holds the credentials can make this mandatory.

## Alternatives considered

**Bare `apply` with the interactive prompt.** The status quo. Rejected for the two reasons in the context: it re-plans on confirmation, and it leaves nothing behind.

**`-auto-approve` everywhere.** Fastest, and no gate at all. Reasonable in a pipeline that has already gated the change upstream; unacceptable as the only path.

**Plan-on-PR via HCP Terraform or Atlantis.** The real answer, and where this should end up — already recorded as an alternative in [ADR 0004](0004-gcs-remote-state.md#alternatives-considered). Rejected here as more infrastructure than a single-project deliverable justifies.

**Wait for CI and do nothing now.** Rejected. The gap is present today, and the cheapest useful gate is one command.
