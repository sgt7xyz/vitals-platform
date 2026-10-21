# Dedicated, least-privilege identity for nodes instead of the Compute Engine default SA
# (which has Editor on the whole project in many orgs).
resource "google_service_account" "gke_nodes" {
  account_id   = "gke-nodes-${var.env}"
  display_name = "GKE node identity (${var.env})"
}

resource "google_project_iam_member" "gke_nodes" {
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_container_cluster" "primary" {
  # checkov:skip=CKV_GCP_12:Dataplane V2 enforces NetworkPolicy; the legacy Calico flag does not apply
  # checkov:skip=CKV_GCP_65:Google Groups for RBAC needs a Workspace domain; tracked for production
  # checkov:skip=CKV_GCP_66:Binary Authorization is a stretch goal (see design doc, known gaps)
  name     = "vitals-${var.env}"
  location = var.zone

  resource_labels = {
    env    = var.env
    system = "vitals-platform"
  }

  network         = google_compute_network.vpc.id
  subnetwork      = google_compute_subnetwork.gke.id
  networking_mode = "VPC_NATIVE"

  # Dataplane V2 (eBPF/Cilium) enforces NetworkPolicy natively.
  datapath_provider = "ADVANCED_DATAPATH"

  # Pod-to-pod traffic on the same node shows up in VPC Flow Logs too.
  enable_intranode_visibility = true

  # Only short-lived Google identities authenticate; no static client certificates.
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # We manage node pools separately so they can be replaced without recreating the cluster.
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false # lab only; true in production

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Nodes get no public IPs. The control plane keeps a public endpoint,
  # locked to your IP by master_authorized_networks_config.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.admin_cidr
      display_name = "admin"
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  enable_shielded_nodes = true

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  # Only used by the throwaway default pool, but keeps it off the default compute SA.
  node_config {
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    disk_size_gb    = 30
    disk_type       = "pd-standard"

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  lifecycle {
    ignore_changes = [node_config]
  }

  depends_on = [
    google_project_service.enabled,
    google_project_iam_member.gke_nodes,
  ]
}

resource "google_container_node_pool" "general" {
  name     = "general"
  cluster  = google_container_cluster.primary.id
  location = var.zone

  initial_node_count = 2

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = "e2-standard-2"
    spot            = true # roughly 60-90% cheaper; fine for a lab, not for prod control loops
    disk_size_gb    = 30
    disk_type       = "pd-standard"
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Pods see the GKE metadata server, so they get Workload Identity
    # instead of the node's credentials.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = {
      pool = "general"
    }
  }
}
