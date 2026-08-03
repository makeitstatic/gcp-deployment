output "cluster_name" {
  value = module.gke.cluster_name
}

output "cluster_location" {
  value = module.gke.cluster_location
}

output "node_service_account" {
  description = "The dedicated least-privilege node SA (proof we are not on the Compute default SA)."
  value       = module.gke.node_service_account
}

output "get_credentials_command" {
  description = "Convenience: fetch kubeconfig for this cluster."
  value       = "gcloud container clusters get-credentials ${module.gke.cluster_name} --region ${module.gke.cluster_location} --project ${var.project_id}"
}
