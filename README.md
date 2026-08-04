# gcp-deploy

Terraform that takes an **empty Google Cloud project** to a private, least-privilege **GKE Autopilot** environment running Google's [Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo), deployed by a script deliberately shaped like a CD job.

The reasoning is part of the deliverable: every significant choice is recorded as an [architecture decision record](docs/decisions/) with the alternatives it beat and what it cost.

| | |
|---|---|
| **Region** | `europe-west4` |
| **Cluster** | GKE Autopilot, regional, private nodes |
| **Terraform** | `>= 1.10` · provider google `~> 6.0` |
| **State** | GCS bucket, versioned, natively locked |
| **Node identity** | Dedicated service account, 5 narrow roles |
| **Workload** | 11 microservices + `redis-cart`, pinned to `v0.10.6` |

## How to read this

Pick the depth you have time for.

**Five minutes** — this page, then [01-context](docs/01-context.md) for what was required and what was deliberately left out.

**Thirty minutes** — add [02-architecture](docs/02-architecture.md) for the three system views and the failure modes, then skim the [ADR index](docs/decisions/). [ADR 0003](docs/decisions/0003-dedicated-node-service-account.md) and [ADR 0005](docs/decisions/0005-mandated-cidr-sizing.md) are the two that say most about how I work.

**An hour, hands on** — follow [04-runbook](docs/04-runbook.md) end to end. It goes from an empty project to a shop answering HTTP 200 in about fifteen minutes, most of it waiting for the cluster, and [tears down](docs/04-runbook.md#teardown) in one command.

**Reviewing the security posture** — [03-security](docs/03-security.md), and specifically its [known gaps](docs/03-security.md#known-gaps), which are listed rather than left to be found.

## Quickstart

Full prerequisites — including the GKE auth plugin and the Application Default Credentials step that trips most people up — are in [04-runbook](docs/04-runbook.md#prerequisites).

```bash
export PROJECT_ID=your-project-id
# fish: set -x PROJECT_ID your-project-id

./scripts/10-preflight.sh                                  # local checks, no credentials
./scripts/20-bootstrap.sh "$PROJECT_ID" <BILLING_ACCOUNT>  # project, billing, state backend
./scripts/30-plan.sh "$PROJECT_ID"                         # read the plan before continuing
./scripts/40-apply.sh                                      # applies exactly that plan, ~10 min
./scripts/50-deploy.sh "$PROJECT_ID"                       # the application
./scripts/60-verify.sh "$PROJECT_ID"                       # assert every requirement

./scripts/70-destroy.sh "$PROJECT_ID"                      # afterwards
```

Tear it down after every session: Cloud NAT and the load balancer bill while idle, and a month of leaving it up costs roughly a hundred times what demonstrating it costs ([05-cost](docs/05-cost.md#the-number-that-matters-more)).

## Documentation

| Document | What it covers |
|---|---|
| [01-context](docs/01-context.md) | The brief, mandatory requirements, **non-goals**, assumptions, what "done" means |
| [02-architecture](docs/02-architecture.md) | System context, infrastructure, application call graph, address plan, failure modes |
| [03-security](docs/03-security.md) | Threat model, the two identity planes, network posture, supply chain, known gaps |
| [04-runbook](docs/04-runbook.md) | Prerequisites, deploy, verify, troubleshoot, tear down |
| [05-cost](docs/05-cost.md) | What Autopilot actually bills, computed from the manifest; free tier versus production |
| [06-roadmap](docs/06-roadmap.md) | What I would do next, ranked, and why |
| [decisions/](docs/decisions/) | Eight ADRs — the *why* behind each choice |

[**solution-architecture.pdf**](solution-architecture.pdf) is all of the above as one document, for reading without cloning. It is generated from the Markdown by [tools/make-pdf.js](tools/make-pdf.js) — never edit it by hand.

## Repository layout

```
.
├── main.tf                 # API enablement + module wiring, nothing else
├── variables.tf            # Mandated CIDRs as defaults, documented
├── versions.tf             # Pinned providers + GCS backend
├── outputs.tf              # Cluster coordinates + proof of the node SA
├── backend.hcl.example     # Bucket name is supplied at init, not in code
├── bootstrap/              # Run once, local state: the state bucket
├── modules/
│   ├── network/            # VPC, subnet + secondary ranges, Router, NAT
│   └── gke/                # Node SA + IAM, private Autopilot cluster
├── scripts/                # Seven ordered stages — the number is the order
│   ├── lib.sh              # Shared helpers and defaults, sourced by each stage
│   ├── 10-preflight.sh     # Tooling, fmt, validate — no credentials, creates nothing
│   ├── 20-bootstrap.sh     # Project, billing, ADC, APIs, state bucket, init
│   ├── 30-plan.sh          # Writes a reviewable tfplan
│   ├── 40-apply.sh         # Applies exactly that plan
│   ├── 50-deploy.sh        # Mock CD: apply + health wait + smoke test
│   ├── 60-verify.sh        # Asserts every requirement, non-zero on failure
│   └── 70-destroy.sh       # Teardown: K8s LBs first, then terraform destroy
├── docs/                   # Documentation; decisions/ holds the ADRs
└── tools/make-pdf.js       # Renders docs/ into solution-architecture.pdf
```

There is no runner and no build tool. Every stage that needs a project takes `PROJECT_ID` as its first argument — 10 takes none because it touches nothing, and 40 takes none because the saved plan already carries the variables. All are safe to re-run and exit non-zero on failure, so a person, a Cloud Build step or a GitHub Actions job can drive the same scripts without anything being ported first.

## The short version of the design

- **Autopilot over Standard** — per-Pod billing, and least privilege becomes structural rather than a checklist: no SSH, no privileged Pods, Shielded nodes always on ([ADR 0001](docs/decisions/0001-gke-autopilot.md)).
- **A dedicated node service account** — GKE nodes otherwise run as the Compute Engine default account, which commonly carries project Editor. One compromised Pod would inherit it ([ADR 0003](docs/decisions/0003-dedicated-node-service-account.md)).
- **Private nodes, NAT-only egress**, and a control-plane endpoint filtered by authorized networks ([ADR 0002](docs/decisions/0002-private-nodes-public-endpoint.md)).
- **Versioned, natively locked remote state** — "collaborate without side effects" is a state problem before it is anything else ([ADR 0004](docs/decisions/0004-gcs-remote-state.md)).
- **The mandated /16s implemented exactly**, with the disagreement about their size recorded rather than silently corrected ([ADR 0005](docs/decisions/0005-mandated-cidr-sizing.md)).
- **A saved plan reviewed before it is applied**, because until CI provides a gate this is the gate ([ADR 0008](docs/decisions/0008-explicit-plan-gate.md)).
- **Requirements asserted, not claimed** — [60-verify.sh](scripts/60-verify.sh) checks the mandated ranges are *bound to the cluster*, that nodes carry the dedicated service account rather than the Compute default, and that the shop answers, then exits non-zero if any of it is untrue.
