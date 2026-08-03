# ------------------------------------------------------------------------------
# Network module — custom-mode VPC + VPC-native GKE ranges + private egress.
#
# Decisions & alternatives:
#
# 1) Custom-mode VPC (auto_create_subnetworks = false)
#    Auto-mode creates a subnet per region with predefined ranges — that would
#    collide with our mandated 10.0.0.0/16 plan and is an anti-pattern for
#    anything beyond experiments. Custom mode = we own the address plan.
#
# 2) VPC-native (alias IP) ranges for Pods/Services
#    The two secondary ranges implement the required 10.1.0.0/16 (Pods) and
#    10.2.0.0/16 (Services). Alternative: routes-based clusters — legacy,
#    no longer recommended, and Autopilot doesn't support them anyway.
#
# 3) Cloud NAT + Private Google Access instead of public node IPs
#    Nodes get NO external IPs (see gke module). Private Google Access lets
#    them reach Google APIs (Artifact Registry, logging) over internal
#    routing; Cloud NAT provides controlled egress for anything external
#    (e.g. pulling an image from Docker Hub) without any inbound exposure.
#    Alternative: public nodes — simpler, but a needlessly larger attack
#    surface; rejected under the least-privilege/security requirement.
# ------------------------------------------------------------------------------

resource "google_compute_network" "vpc" {
  name                    = var.network_name
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "gke" {
  name    = "${var.network_name}-gke"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id

  # Nodes: 10.0.0.0/16 (challenge requirement)
  ip_cidr_range = var.subnet_nodes_cidr

  # Pods: 10.1.0.0/16 (challenge requirement)
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  # Services: 10.2.0.0/16 (challenge requirement)
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  # Reach Google APIs without public IPs.
  private_ip_google_access = true

  # VPC Flow Logs: cheap, sampled network telemetry for security forensics
  # and troubleshooting. 50% sampling keeps demo cost negligible.
  log_config {
    aggregation_interval = "INTERVAL_5_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# --- Controlled egress for private nodes -------------------------------------
resource "google_compute_router" "router" {
  name    = "${var.network_name}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name    = "${var.network_name}-nat"
  project = var.project_id
  region  = var.region
  router  = google_compute_router.router.name

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # Log NAT errors only — enough signal for debugging blocked egress
  # without paying for every translation event.
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
