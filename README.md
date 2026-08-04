# Online Boutique on Google Cloud

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

# Prerequisites: tooling, auth, billing, ADC, APIs, validation — idempotent
./scripts/setup.sh "$PROJECT_ID" <BILLING_ACCOUNT_ID>

# State bucket, once per project
cd bootstrap && terraform init && terraform apply -var="project_id=$PROJECT_ID" && cd ..

# Platform, ~10 min
sed "s/YOUR_PROJECT_ID/$PROJECT_ID/" backend.hcl.example > backend.hcl
terraform init -backend-config=backend.hcl
terraform apply -var="project_id=$PROJECT_ID"

# Application, then verify
./scripts/deploy.sh "$PROJECT_ID"

# Afterwards — from the repository root
./scripts/destroy.sh "$PROJECT_ID"
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
| [decisions/](docs/decisions/) | Seven ADRs — the *why* behind each choice |

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
├── scripts/
│   ├── setup.sh            # Prerequisites: auth, billing, ADC, APIs, validate
│   ├── deploy.sh           # Mock CD: apply + health wait + smoke test
│   └── destroy.sh          # Teardown: K8s LBs first, then terraform destroy
├── docs/                   # Documentation; decisions/ holds the ADRs
└── tools/make-pdf.js       # Renders docs/ into solution-architecture.pdf
```

## The short version of the design

- **Autopilot over Standard** — per-Pod billing, and least privilege becomes structural rather than a checklist: no SSH, no privileged Pods, Shielded nodes always on ([ADR 0001](docs/decisions/0001-gke-autopilot.md)).
- **A dedicated node service account** — GKE nodes otherwise run as the Compute Engine default account, which commonly carries project Editor. One compromised Pod would inherit it ([ADR 0003](docs/decisions/0003-dedicated-node-service-account.md)).
- **Private nodes, NAT-only egress**, and a control-plane endpoint filtered by authorized networks ([ADR 0002](docs/decisions/0002-private-nodes-public-endpoint.md)).
- **Versioned, natively locked remote state** — "collaborate without side effects" is a state problem before it is anything else ([ADR 0004](docs/decisions/0004-gcs-remote-state.md)).
- **The mandated /16s implemented exactly**, with the disagreement about their size recorded rather than silently corrected ([ADR 0005](docs/decisions/0005-mandated-cidr-sizing.md)).
