output "cluster_name" {
  value = module.gke.cluster_name
}

output "cluster_location" {
  value = module.gke.cluster_location
}

output "node_service_account" {
  description = "The dedicated node service account, not the Compute Engine default."
  value       = module.gke.node_service_account
}

output "get_credentials_command" {
  description = "Fetch kubeconfig for this cluster."
  value       = "gcloud container clusters get-credentials ${module.gke.cluster_name} --region ${module.gke.cluster_location} --project ${var.project_id}"
}
