# ------------------------------------------------------------------------------
# BOOTSTRAP — run once, with local state, before anything else.
#
# Chicken-and-egg problem: Terraform needs a remote backend for team
# collaboration, but the backend bucket itself must be created by *something*.
# This tiny root module solves that. Its own state is local and thereafter
# irrelevant (the bucket is protected by prevent_destroy).
#
#   cd bootstrap
#   terraform init && terraform apply -var="project_id=<PROJECT_ID>"
# ------------------------------------------------------------------------------

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

  # --- Collaboration & safety controls -----------------------------------
  # Versioning lets us roll back a corrupted/incorrectly-pushed state file.
  versioning {
    enabled = true
  }

  # Uniform bucket-level access: IAM only, no per-object ACLs. One access
  # model to reason about = fewer least-privilege mistakes.
  uniform_bucket_level_access = true

  # State contains secrets-adjacent data (resource IDs, sometimes outputs).
  # Never expose it publicly.
  public_access_prevention = "enforced"

  # Belt-and-braces: refuse to destroy the bucket via Terraform.
  lifecycle {
    prevent_destroy = true
  }

  # Keep the last 10 noncurrent state versions, drop older ones.
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
  description = "Pass this to the root module: terraform init -backend-config=\"bucket=<this>\""
  value       = google_storage_bucket.tf_state.name
}
