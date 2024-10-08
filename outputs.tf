output "console_url" {
  value = "http://${google_compute_global_forwarding_rule.redpanda_http.ip_address}"
}
