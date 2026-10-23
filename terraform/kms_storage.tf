# Customer-managed encryption keys (CMEK) for the bucket that stands in for PHI.
# NOTE: key rings can never be deleted in GCP. After a destroy, re-running apply with
# the same name needs `terraform import` (see the lab's teardown section).
resource "google_kms_key_ring" "vitals" {
  name     = "vitals-${var.env}"
  location = var.region

  depends_on = [google_project_service.enabled]
}

resource "google_kms_crypto_key" "phi" {
  # checkov:skip=CKV_GCP_82:lab must be destroyable; production adds lifecycle { prevent_destroy = true }
  name            = "phi-data"
  key_ring        = google_kms_key_ring.vitals.id
  rotation_period = "7776000s" # 90 days
}

# The Cloud Storage service agent encrypts/decrypts on our behalf, so it needs the key.
data "google_storage_project_service_account" "gcs" {}

resource "google_kms_crypto_key_iam_member" "gcs_uses_key" {
  crypto_key_id = google_kms_crypto_key.phi.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}

resource "google_storage_bucket" "phi" {
  # checkov:skip=CKV_GCP_62:Data Access audit logs (audit.tf) record every read and write
  name     = "${var.project_id}-phi-${var.env}"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true # lab only

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.phi.id
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    data-classification = "phi-synthetic"
  }

  depends_on = [google_kms_crypto_key_iam_member.gcs_uses_key]
}

# Synthetic record so the Workload Identity test has something to read. Never real PHI.
resource "google_storage_bucket_object" "sample" {
  name   = "synthetic/patient-0001.json"
  bucket = google_storage_bucket.phi.name
  content = jsonencode({
    patient_id = "SYN-0001"
    heart_rate = 72
    spo2       = 98
    note       = "Synthetic test record"
  })
}

# Workload Identity Federation for GKE, direct principal style: the Kubernetes
# ServiceAccount toolbox/phi-reader gets read access with no Google SA and no key.
resource "google_storage_bucket_iam_member" "phi_reader" {
  bucket = google_storage_bucket.phi.name
  role   = "roles/storage.objectViewer"
  member = "principal://iam.googleapis.com/projects/${data.google_project.this.number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/toolbox/sa/phi-reader"

  depends_on = [google_container_cluster.primary] # the workload pool exists once the cluster does
}
