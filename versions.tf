# ------------------------------------------------------------------------------
# Terraform & provider version pinning + remote backend.
#
# Why pin? Different engineers running different provider versions against the
# same state is a classic source of "works on my machine" drift. Pinning the
# major version (~> 6.0) plus committing .terraform.lock.hcl gives everyone
# byte-identical providers.
#
# Why a GCS backend? Requirement "Ops": engineers must collaborate without
# side effects. GCS gives us:
#   - a single shared source of truth for state
#   - native state locking (lock object per state file) -> two engineers
#     cannot run `apply` concurrently and corrupt state
#   - object versioning (configured in ./bootstrap) -> state history/rollback
#
# The bucket name is intentionally NOT hardcoded (it is project-specific).
# Initialise with:
#   terraform init -backend-config="bucket=<PROJECT_ID>-tf-state"
# or with the committed example file:
#   terraform init -backend-config=backend.hcl
# ------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  backend "gcs" {
    prefix = "online-boutique/root"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
