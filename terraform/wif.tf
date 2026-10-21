# Keyless CI: GitHub Actions exchanges its OIDC token for short-lived Google credentials.
# No JSON service-account keys exist anywhere.
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.enabled]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  # checkov:skip=CKV_GCP_125:attribute_condition pins the exact repository via var.github_repo
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Without this, ANY GitHub repo could mint tokens against the pool.
  attribute_condition = "assertion.repository == \"${var.github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

locals {
  github_principal = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

# --- Image builder: can only push images to one repository ---
resource "google_service_account" "gha_builder" {
  account_id   = "gha-builder"
  display_name = "GitHub Actions image builder"
}

resource "google_artifact_registry_repository_iam_member" "builder_push" {
  repository = google_artifact_registry_repository.vitals.name
  location   = google_artifact_registry_repository.vitals.location
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.gha_builder.email}"
}

resource "google_service_account_iam_member" "builder_wif" {
  service_account_id = google_service_account.gha_builder.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.github_principal
}

# --- Terraform runner: broad, because it manages the platform itself ---
# Interview talking point: in production split this into a read-only "plan" identity
# usable from pull requests and a write "apply" identity bound to refs/heads/main only.
resource "google_service_account" "gha_terraform" {
  account_id   = "gha-terraform"
  display_name = "GitHub Actions Terraform runner"
}

resource "google_project_iam_member" "terraform_runner" {
  # checkov:skip=CKV_GCP_49:the platform runner must manage service accounts; split plan/apply identities in production
  # checkov:skip=CKV_GCP_117:accepted lab risk; documented as a known gap in docs/design-doc.md
  for_each = toset([
    "roles/editor",
    "roles/resourcemanager.projectIamAdmin",
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/cloudkms.admin",
    "roles/storage.admin",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gha_terraform.email}"
}

resource "google_service_account_iam_member" "terraform_wif" {
  service_account_id = google_service_account.gha_terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.github_principal
}
