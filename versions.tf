# State lives in GCS so two engineers cannot apply over each other. The bucket
# is locked natively and versioned; see ADR 0004.
#
# The bucket name is project-specific, so it is supplied at init:
#   terraform init -backend-config=backend.hcl

terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  backend "gcs" {
    prefix = "gcp-deploy/root"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
