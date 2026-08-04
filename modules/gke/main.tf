# Private Autopilot cluster with a dedicated node service account.
# Reasoning: ADRs 0001, 0002, 0003.

# --- Node identity ------------------------------------------------------------

# GKE nodes default to the Compute Engine service account, which usually holds
# project Editor. This replaces it.
resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-nodes"
  display_name = "GKE node SA for ${var.cluster_name}"
}

locals {
  # The minimum Google documents for a working node.
  node_sa_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/artifactregistry.reader",
    "roles/stackdriver.resourceMetadata.writer",
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
  location = var.region # regional: control plane and nodes across three zones

  enable_autopilot = true

  network    = var.network_id
  subnetwork = var.subnet_id

  # Binds the mandated Pod and Service ranges to the cluster.
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Nodes get no public IPs. The control plane endpoint stays public, filtered
  # by master_authorized_networks below. See ADR 0002.
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

  # On Autopilot this block is the only way to set the node service account.
  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = google_service_account.gke_nodes.email
      oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  # Off by default: the upstream images are unsigned. See ADR 0006.
  dynamic "binary_authorization" {
    for_each = var.enable_binary_authorization ? [1] : []
    content {
      evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
    }
  }

  # False so the demo can be torn down. Stays true in production.
  deletion_protection = false

  depends_on = [google_project_iam_member.node_sa]
}
