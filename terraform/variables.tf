variable "project_id" {
  description = "GCP project that hosts the lab."
  type        = string
}

variable "region" {
  description = "Primary region. us-east1 (South Carolina) is closest to the Triangle."
  type        = string
  default     = "us-east1"
}

variable "zone" {
  description = "Zone for the zonal GKE cluster (one zonal cluster is covered by the GKE free tier credit)."
  type        = string
  default     = "us-east1-b"
}

variable "env" {
  description = "Environment name, used in names and labels."
  type        = string
  default     = "dev"
}

variable "github_repo" {
  description = "GitHub repository allowed to authenticate through Workload Identity Federation, as owner/name."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repo))
    error_message = "github_repo must look like owner/name."
  }
}

variable "admin_cidr" {
  description = "Your public IP as a /32. Only this range can reach the GKE control plane."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0))
    error_message = "admin_cidr must be valid CIDR notation, for example 203.0.113.7/32."
  }
}

variable "alert_email" {
  description = "Email address that receives monitoring alerts."
  type        = string
}

variable "slo_goal" {
  description = "Availability objective for the Vitals API."
  type        = number
  default     = 0.999
}
