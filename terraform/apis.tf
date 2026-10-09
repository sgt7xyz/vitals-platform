locals {
  services = toset([
    "artifactregistry.googleapis.com",
    "cloudkms.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "sts.googleapis.com",
  ])
}

resource "google_project_service" "enabled" {
  for_each = local.services

  service            = each.value
  disable_on_destroy = false # never let a destroy switch off an API other teams may use
}
