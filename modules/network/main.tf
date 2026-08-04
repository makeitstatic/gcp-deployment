# VPC, the subnet carrying all three mandated ranges, and NAT egress for the
# private nodes.

resource "google_compute_network" "vpc" {
  name    = var.network_name
  project = var.project_id

  # Custom mode. Auto mode picks its own ranges per region and would collide
  # with the mandated address plan.
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "gke" {
  name    = "${var.network_name}-gke"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id

  # Nodes.
  ip_cidr_range = var.subnet_nodes_cidr

  # Pods and Services, as alias IP ranges. The GKE module binds them by name.
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  # Lets nodes reach Google APIs without public IPs.
  private_ip_google_access = true

  # Sampled at 50%: enough for forensics, cheap enough for a demo.
  log_config {
    aggregation_interval = "INTERVAL_5_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# --- Egress for private nodes -------------------------------------------------

# Nodes have no external IPs, so anything not on Google's network (a Docker Hub
# pull, for example) leaves through here.

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

  # Errors only. Logging every translation is expensive and rarely read.
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
