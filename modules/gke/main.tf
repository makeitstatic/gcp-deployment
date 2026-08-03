# ------------------------------------------------------------------------------
# GKE module — private Autopilot cluster with a least-privilege identity chain.
#
# Decisions & alternatives:
#
# 1) Autopilot vs Standard vs (Cloud Run / GCE MIGs)
#    - Autopilot (CHOSEN): Google operates the nodes (patching, upgrades,
#      right-sizing); you pay per Pod request, which directly serves the
#      "improve resource utilization to optimise cost" goal from Part 1.
#      Security posture is opinionated-by-default: Shielded nodes, Workload
#      Identity, no privileged Pods, no SSH to nodes — least privilege as a
#      platform property, not a checklist. 
#    - Standard: more knobs (custom node pools, DaemonSet freedom, GPUs
#      without constraints). I'd switch if we needed node-level agents or
#      exotic tuning; nothing in Online Boutique requires it.
#    - Cloud Run: even less ops, but Online Boutique ships as Kubernetes
#      manifests incl. a gRPC service mesh of 10+ services and a Redis
#      StatefulSet-ish component; GKE is the intended and lowest-friction
#      target, and matches the Part-1 target architecture (GKE Autopilot,
#      per-tenant namespaces).
#
# 2) Private nodes, public (but authorized-network-guarded) endpoint
#    Nodes have zero public IPs -> no direct inbound path to workloads
#    except through load balancers we deliberately create. The control-plane
#    endpoint stays public for demo ergonomics but is guarded by
#    master_authorized_networks. Production hardening: private endpoint +
#    IAP tunnel or Connect Gateway.
#
# 3) Dedicated node service account (the big least-privilege win)
#    By default GKE nodes run as the Compute Engine *default* SA, which
#    historically carries the project Editor role — a lateral-movement
#    dream for an attacker who compromises one Pod. We create a dedicated SA
#    with exactly four narrowly scoped roles (logs, metrics, image pull).
#    Workloads themselves get identity via Workload Identity (GSA<->KSA
#    binding), never via node credentials or exported JSON keys.
# ------------------------------------------------------------------------------

# --- Least-privilege node identity -------------------------------------------
resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-nodes"
  display_name = "Least-privilege GKE node SA for ${var.cluster_name}"
}

locals {
  # The minimal set Google documents for functioning nodes — nothing more.
  node_sa_roles = [
    "roles/logging.logWriter",                 # ship node/Pod logs
    "roles/monitoring.metricWriter",           # ship metrics
    "roles/monitoring.viewer",                 # GKE metrics agent reads
    "roles/artifactregistry.reader",           # pull images from AR
    "roles/stackdriver.resourceMetadata.writer" # resource metadata for observability
  ]
}

resource "google_project_iam_member" "node_sa" {
  for_each = toset(local.node_sa_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# --- Cluster ------------------------------------------------------------------
resource "google_container_cluster" "autopilot" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.region # regional: control plane + workloads spread over 3 zones

  enable_autopilot = true

  network    = var.network_id
  subnetwork = var.subnet_id

  # Bind the mandated secondary ranges (VPC-native / alias IP).
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Nodes without public IPs; control plane peered via a dedicated /28.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  # Autopilot provisions nodes on demand; this pins those nodes to our
  # least-privilege SA instead of the Compute Engine default SA.
  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = google_service_account.gke_nodes.email
      oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  }

  # REGULAR channel: automatic, Google-validated upgrades — patching toil
  # and CVE exposure handled by the platform. Alternative: STABLE (slower,
  # for change-averse orgs) or RAPID (early features).
  release_channel {
    channel = "REGULAR"
  }

  # Delivery gate: only signed/attested images admitted, when enabled.
  # Off by default here because the public sample images are unsigned.
  dynamic "binary_authorization" {
    for_each = var.enable_binary_authorization ? [1] : []
    content {
      evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
    }
  }

  # Demo ergonomics: allow `terraform destroy` to actually work.
  # In production this stays true and deletion goes through change control.
  deletion_protection = false

  depends_on = [google_project_iam_member.node_sa]
}
