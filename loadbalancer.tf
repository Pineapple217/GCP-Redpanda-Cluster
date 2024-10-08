resource "google_compute_global_address" "redpanda_lb_ip" {
  name = "${var.prefix}-redpanda-lb-ip"
}

resource "google_compute_health_check" "default" {
  name = "${var.prefix}-redpanda-console-health-check"
  http_health_check {
    port = 80
    request_path = "/"
  }
  check_interval_sec = 5
  timeout_sec        = 5
  healthy_threshold  = 2
  unhealthy_threshold = 2
}

resource "google_compute_backend_service" "default" {
  name                  = "${var.prefix}-redpanda-console-backend"
  protocol              = "HTTP"
  port_name             = "console"
  timeout_sec           = 10
  connection_draining_timeout_sec = 30
  health_checks         = [google_compute_health_check.default.id]

  backend {
    group = google_compute_instance_group.cluster.self_link
  }
}

resource "google_compute_url_map" "default" {
  name            = "${var.prefix}-redpanda-url-map"
  default_service = google_compute_backend_service.default.self_link
}

resource "google_compute_target_http_proxy" "default" {
  name    = "${var.prefix}-redpanda-http-proxy"
  url_map = google_compute_url_map.default.id
}

resource "google_compute_global_forwarding_rule" "redpanda_http" {
  name       = "${var.prefix}-redpanda-http-forwarding-rule"
  ip_address = google_compute_global_address.redpanda_lb_ip.address
  port_range = "80"
  target     = google_compute_target_http_proxy.default.id
}
