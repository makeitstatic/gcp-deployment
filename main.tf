# ------------------------------------------------------------------------------
# Root composition.
#
# Structure decision: a thin root that only wires modules together.
#   modules/network -> VPC, subnet + secondary ranges, Cloud Router, Cloud NAT
#   modules/gke     -> least-privilege node SA, GKE Autopilot private cluster
#
# Why modules at all for something this small? The Ops requirement. Modules
# give reviewable blast-radius boundaries, enable per-module ownership, and
# are the unit of reuse when this pattern is stamped out per environment
# (dev/stage/prod directories or workspaces) later.
# ------------------------------------------------------------------------------

# --- Enable required APIs -----------------------------------------------------
# Codifying API enablement means a brand-new empty project converges with a
# single `terraform apply` — no clickops prerequisites for a colleague.
locals {
  services = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com", # Workload Identity Federation for CI
    "cloudresourcemanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "binaryauthorization.googleapis.com",
  ]
}

resource "google_project_service" "required" {
  for_each = toset(local.services)
  service  = each.value

  # Don't disable APIs on destroy: other resources/projects may rely on them
  # and re-enabling is slow. Destroy should remove OUR resources, not
  # project-level capabilities.
  disable_on_destroy = false
}

# --- Network ------------------------------------------------------------------
module "network" {
  source = "./modules/network"

  project_id        = var.project_id
  region            = var.region
  network_name      = "${var.cluster_name}-vpc"
  subnet_nodes_cidr = var.subnet_nodes_cidr
  pods_cidr         = var.pods_cidr
  services_cidr     = var.services_cidr

  depends_on = [google_project_service.required]
}

# --- GKE ----------------------------------------------------------------------
module "gke" {
  source = "./modules/gke"

  project_id                  = var.project_id
  region                      = var.region
  cluster_name                = var.cluster_name
  network_id                  = module.network.network_id
  subnet_id                   = module.network.subnet_id
  pods_range_name             = module.network.pods_range_name
  services_range_name         = module.network.services_range_name
  master_ipv4_cidr            = var.master_ipv4_cidr
  authorized_networks         = var.authorized_networks
  enable_binary_authorization = var.enable_binary_authorization

  depends_on = [google_project_service.required]
}
