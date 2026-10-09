resource "google_artifact_registry_repository" "vitals" {
  # checkov:skip=CKV_GCP_84:images hold no sensitive data; Google-managed encryption is acceptable
  repository_id = "vitals"
  location      = var.region
  format        = "DOCKER"
  description   = "Container images for the Vitals platform"

  # A tag, once pushed, always points at the same image. Deploys are reproducible
  # and an attacker with push rights cannot silently swap an image under a tag.
  docker_config {
    immutable_tags = true
  }

  depends_on = [google_project_service.enabled]
}
