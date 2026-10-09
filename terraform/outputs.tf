output "get_credentials" {
  description = "Run this to point kubectl at the cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --zone ${var.zone} --project ${var.project_id}"
}

output "lb_ip" {
  description = "Static IP to paste into k8s/overlays/dev/service-patch.yaml."
  value       = google_compute_address.vitals_lb.address
}

output "image_repo" {
  description = "Artifact Registry path for the app image."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.vitals.repository_id}"
}

output "wif_provider" {
  description = "Value for the GCP_WIF_PROVIDER GitHub variable."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "gha_terraform_sa" {
  value = google_service_account.gha_terraform.email
}

output "gha_builder_sa" {
  value = google_service_account.gha_builder.email
}

output "phi_bucket" {
  value = google_storage_bucket.phi.name
}
