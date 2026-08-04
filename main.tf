# Wires the two modules together. Nothing else lives here.
# Split into modules so engineers can own and change them separately, which is
# what the Ops requirement asks for.

locals {
  services = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "binaryauthorization.googleapis.com",
  ]
}

# Enabling these in code means an empty project needs no manual setup first.
resource "google_project_service" "required" {
  for_each = toset(local.services)
  service  = each.value

  # Leave them enabled on destroy — other things in the project may need them.
  disable_on_destroy = false
}

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
