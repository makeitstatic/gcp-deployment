output "cluster_name" {
  value = google_container_cluster.autopilot.name
}

output "cluster_location" {
  value = google_container_cluster.autopilot.location
}

output "node_service_account" {
  value = google_service_account.gke_nodes.email
}
