variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "network_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "pods_range_name" {
  type = string
}

variable "services_range_name" {
  type = string
}

variable "master_ipv4_cidr" {
  type = string
}

variable "authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
}

variable "enable_binary_authorization" {
  type = bool
}
