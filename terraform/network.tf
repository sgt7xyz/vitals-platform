resource "google_compute_network" "vpc" {
  name                    = "vitals-${var.env}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.enabled]
}

resource "google_compute_subnetwork" "gke" {
  name                     = "gke-${var.env}-${var.region}"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.10.0.0/20"
  private_ip_google_access = true # private nodes reach Google APIs without public IPs

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.30.0.0/20"
  }

  # VPC Flow Logs: network evidence for incident response and HIPAA audit controls.
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud NAT gives private nodes outbound internet (image pulls from GitHub/Docker Hub,
# Argo CD reaching GitHub) without any node having a public IP.
resource "google_compute_router" "nat" {
  name    = "vitals-${var.env}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "vitals-${var.env}-nat"
  router                             = google_compute_router.nat.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Explicit, logged deny-all at the lowest priority. GKE adds its own allow rules at
# priority 1000, so this only catches traffic nobody intended to allow.
resource "google_compute_firewall" "deny_all_ingress" {
  name      = "vitals-${var.env}-deny-all-ingress"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Static IP owned by Terraform. The Kubernetes Service claims it, and the uptime
# check targets it, so the IP is known before the app ever deploys.
resource "google_compute_address" "vitals_lb" {
  name         = "vitals-${var.env}-lb"
  region       = var.region
  address_type = "EXTERNAL"

  depends_on = [google_project_service.enabled]
}
