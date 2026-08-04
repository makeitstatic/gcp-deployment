# Creates the GCS bucket that holds the root module's state. Runs once, with
# local state, because a backend cannot create its own bucket.
#
#   cd bootstrap
#   terraform init && terraform apply -var="project_id=<PROJECT_ID>"

terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

variable "project_id" {
  description = "GCP project that will hold the Terraform state bucket."
  type        = string
}

variable "region" {
  description = "Region for the state bucket."
  type        = string
  default     = "europe-west4"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_project_service" "storage" {
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_storage_bucket" "tf_state" {
  name     = "${var.project_id}-tf-state"
  location = var.region

  # Roll back a corrupted or wrongly-pushed state file.
  versioning {
    enabled = true
  }

  # IAM only, no per-object ACLs.
  uniform_bucket_level_access = true

  public_access_prevention = "enforced"

  lifecycle {
    prevent_destroy = true
  }

  # Keep the last 10 old versions.
  lifecycle_rule {
    condition {
      num_newer_versions = 10
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.storage]
}

output "state_bucket" {
  description = "Pass to the root module: terraform init -backend-config=\"bucket=<this>\""
  value       = google_storage_bucket.tf_state.name
}
