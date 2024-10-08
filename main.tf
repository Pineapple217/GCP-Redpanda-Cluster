terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

provider "google" {
  project = var.project
  region = var.region
  zone = var.zone
}

resource "google_compute_network" "default" {
  name = "main-network"
}

resource "google_compute_subnetwork" "default" {
  name          = "cluster-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.default.id
}

resource "google_compute_firewall" "default" {
  name    = "redpanda-firewall"
  network = google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = ["9092", "8082", "8081", "9644", "33145", "80"]
  }
  source_ranges = ["10.0.0.0/24"]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh-ingress-from-iap"
  network = google_compute_network.default.name

  direction = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["allow-ssh-ingress"]
}

resource "google_compute_router" "nat_router" {
  name    = "redpanda-nat-router"
  region  = var.region
  network = google_compute_network.default.id
}

resource "google_compute_router_nat" "nat_config" {
  name                              = "redpanda-nat-config"
  router                            = google_compute_router.nat_router.name
  region                            = var.region
  nat_ip_allocate_option            = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_service_account" "default" {
  account_id   = "redpanda-cluster"
  display_name = "Redpanda Cluster"
}

resource "google_compute_instance_template" "redpanda_broker" {
  name        = "redpanda-broker-template"
  description = "Redpanda broker template"

  instance_description = "Redpanda broker"
  machine_type         = "n1-standard-1"
  can_ip_forward       = false

  disk {
    source_image      = "debian-cloud/debian-12"
    auto_delete       = true
    boot              = true
    disk_size_gb      = 10
  }

  dynamic "disk" {
    for_each = range(2)
    content {
      device_name = "local-nvme-${disk.value}"
      boot  = false
      interface = "NVME"
      type = "SCRATCH"
      disk_type = "local-ssd"
      disk_size_gb = 375
    }
  }

  network_interface {
    access_config {
      nat_ip = ""
      network_tier = "STANDARD"
    }
    subnetwork  = google_compute_subnetwork.default.name
  }
  tags = [ "http-server", "https-server", "lb-health-check", "allow-ssh-ingress"]

  scheduling {
    preemptible = true
    automatic_restart = false
  }

  service_account {
    email = google_service_account.default.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}

resource "google_compute_instance_from_template" "redpanda_broker" {
  count = var.node_count
  name  = "rp-broker-${count.index}"
  zone = var.zone
  source_instance_template = google_compute_instance_template.redpanda_broker.name

  network_interface {
    subnetwork  = google_compute_subnetwork.default.name
    network_ip  = google_compute_address.redpanda_addresses[count.index].address
  }

  metadata_startup_script = templatefile("${path.module}/startup.tftpl", {
    ips      = join(",", google_compute_address.redpanda_addresses[*].address)
    brokers  = join(",", [for addr in google_compute_address.redpanda_addresses[*].address : format("\"%s:9092\"", addr)])
    url      = google_compute_address.redpanda_addresses[count.index].address
  })
}

resource "google_compute_address" "redpanda_addresses" {
  count      = var.node_count
  name       = "redpanda-static-ip-${count.index + 1}"
  address_type = "INTERNAL"
  subnetwork = google_compute_subnetwork.default.name
}

resource "google_compute_instance_group" "cluster" {
  name        = "redpanda-cluster"
  description = "Redpanda Cluster"

  instances = google_compute_instance_from_template.redpanda_broker[*].id
  network = google_compute_network.default.id

  named_port {
    name = "console"
    port = 80
  }

  zone = var.zone
}

resource "google_compute_global_address" "redpanda_lb_ip" {
  name = "redpanda-lb-ip"
}

resource "google_compute_health_check" "default" {
  name = "redpanda-console-health-check"
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
  name                  = "redpanda-console-backend"
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
  name            = "redpanda-url-map"
  default_service = google_compute_backend_service.default.self_link
}

resource "google_compute_target_http_proxy" "default" {
  name    = "redpanda-http-proxy"
  url_map = google_compute_url_map.default.id
}

resource "google_compute_global_forwarding_rule" "redpanda_http" {
  name       = "redpanda-http-forwarding-rule"
  ip_address = google_compute_global_address.redpanda_lb_ip.address
  port_range = "80"
  target     = google_compute_target_http_proxy.default.id
}
