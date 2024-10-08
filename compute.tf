resource "google_service_account" "default" {
  account_id   = "${var.prefix}-redpanda-cluster"
  display_name = "${var.prefix} Redpanda Cluster"
}

resource "google_compute_instance_template" "redpanda_broker" {
  name        = "${var.prefix}-redpanda-broker-template"
  description = "${var.prefix} Redpanda broker template"

  instance_description = "Redpanda broker instance for ${var.prefix}"
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
  tags = [ "http-server", "lb-health-check", "allow-ssh"]

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
  count = var.broker_count
  name  = "${var.prefix}-rp-broker-${count.index}"
  zone = var.zone
  source_instance_template = google_compute_instance_template.redpanda_broker.name

  network_interface {
    subnetwork  = google_compute_subnetwork.default.name
    network_ip  = google_compute_address.static[count.index].address
  }

  metadata_startup_script = templatefile("${path.module}/startup.tftpl", {
    ips      = join(",", google_compute_address.static[*].address)
    brokers  = join(",", [for addr in google_compute_address.static[*].address : format("\"%s:9092\"", addr)])
    url      = google_compute_address.static[count.index].address
  })
}

resource "google_compute_address" "static" {
  count      = var.broker_count
  name       = "${var.prefix}-redpanda-static-ip-${count.index + 1}"
  address_type = "INTERNAL"
  subnetwork = google_compute_subnetwork.default.name
}

resource "google_compute_instance_group" "cluster" {
  name        = "${var.prefix}-redpanda-cluster"
  description = "Redpanda Cluster"

  instances = google_compute_instance_from_template.redpanda_broker[*].id
  network = google_compute_network.default.id

  named_port {
    name = "console"
    port = 80
  }

  zone = var.zone
}