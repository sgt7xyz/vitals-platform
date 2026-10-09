resource "google_monitoring_notification_channel" "email" {
  display_name = "Platform on-call email"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }

  depends_on = [google_project_service.enabled]
}

# ---------- Black-box: is the API reachable from the internet? ----------
resource "google_monitoring_uptime_check_config" "vitals" {
  display_name = "vitals-api-healthz"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = "/healthz"
    port         = 80
    validate_ssl = false
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = google_compute_address.vitals_lb.address
    }
  }
}

resource "google_monitoring_alert_policy" "uptime" {
  display_name = "Vitals API unreachable"
  combiner     = "OR"

  conditions {
    display_name = "Uptime check failing from 2+ regions"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.check_id=\"${google_monitoring_uptime_check_config.vitals.uptime_check_id}\" AND resource.type=\"uptime_url\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "300s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.*"]
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  documentation {
    content   = "Runbook: docs/runbook-high-error-rate.md. Check Argo CD sync status, then `kubectl -n vitals get pods,svc`."
    mime_type = "text/markdown"
  }
}

# ---------- White-box: SLO built on the app's own Prometheus metrics ----------
resource "google_monitoring_custom_service" "vitals" {
  service_id   = "vitals-api"
  display_name = "Vitals API"

  depends_on = [google_project_service.enabled]
}

locals {
  # Managed Service for Prometheus exposes counter `vitals_http_requests_total`
  # as this Cloud Monitoring metric type.
  requests_metric = "metric.type=\"prometheus.googleapis.com/vitals_http_requests_total/counter\" resource.type=\"prometheus_target\" resource.label.namespace=\"vitals\""
}

resource "google_monitoring_slo" "availability" {
  service      = google_monitoring_custom_service.vitals.service_id
  slo_id       = "availability"
  display_name = "99.9% of API requests succeed (28d rolling)"

  goal                = var.slo_goal
  rolling_period_days = 28

  request_based_sli {
    good_total_ratio {
      bad_service_filter   = "${local.requests_metric} metric.label.code_class=\"5xx\""
      total_service_filter = local.requests_metric
    }
  }
}

# Multi-window burn-rate alerting (Google SRE workbook, chapter 5):
#  fast burn 14.4x over 1h = 2% of the 28-day budget gone in an hour -> page
#  slow burn 6x over 6h    = 5% of the budget gone in six hours     -> page
resource "google_monitoring_alert_policy" "slo_burn" {
  display_name = "Vitals API burning error budget"
  combiner     = "OR"

  conditions {
    display_name = "Fast burn (14.4x, 1h)"
    condition_threshold {
      filter          = "select_slo_burn_rate(\"${google_monitoring_slo.availability.name}\", \"60m\")"
      comparison      = "COMPARISON_GT"
      threshold_value = 14.4
      duration        = "0s"
    }
  }

  conditions {
    display_name = "Slow burn (6x, 6h)"
    condition_threshold {
      filter          = "select_slo_burn_rate(\"${google_monitoring_slo.availability.name}\", \"360m\")"
      comparison      = "COMPARISON_GT"
      threshold_value = 6
      duration        = "0s"
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  documentation {
    content   = "Error budget burning. Runbook: docs/runbook-high-error-rate.md"
    mime_type = "text/markdown"
  }
}

# ---------- Logs: count application errors ----------
resource "google_logging_metric" "vitals_errors" {
  name   = "vitals_api_errors"
  filter = "resource.type=\"k8s_container\" AND resource.labels.namespace_name=\"vitals\" AND severity>=ERROR"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }

  depends_on = [google_project_service.enabled]
}

resource "google_monitoring_dashboard" "vitals" {
  dashboard_json = file("${path.module}/dashboards/vitals.json")

  depends_on = [google_project_service.enabled]
}
