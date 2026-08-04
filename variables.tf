variable "project_id" {
  description = "GCP project ID to deploy into."
  type        = string
}

variable "region" {
  description = "Deployment region. europe-west4 for low latency from the Netherlands."
  type        = string
  default     = "europe-west4"
}

variable "cluster_name" {
  description = "Name of the GKE cluster. Also prefixes the VPC and the node service account."
  type        = string
  default     = "gcp-deploy"
}

# Node, Pod and Service ranges are fixed by the brief.
# The /16s are far larger than this workload needs — see ADR 0005.

variable "subnet_nodes_cidr" {
  description = "Primary subnet range (GKE nodes)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "pods_cidr" {
  description = "Secondary range for Pods."
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "Secondary range for Services."
  type        = string
  default     = "10.2.0.0/16"
}

variable "master_ipv4_cidr" {
  description = "RFC1918 /28 for the control plane. Must not overlap the ranges above."
  type        = string
  default     = "172.16.0.0/28"
}

variable "authorized_networks" {
  description = "CIDRs allowed to reach the control plane endpoint. Open by default to keep the demo reproducible; restrict in production. See ADR 0002."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [{
    cidr_block   = "0.0.0.0/0"
    display_name = "demo-open (lock down in prod)"
  }]
}

variable "enable_binary_authorization" {
  description = "Enforce Binary Authorization. Off by default because the upstream images are unsigned. See ADR 0006."
  type        = bool
  default     = false
}
