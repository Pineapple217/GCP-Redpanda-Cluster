resource "google_compute_network" "default" {
  name = "${var.prefix}-main-network"
}

resource "google_compute_subnetwork" "default" {
  name          = "${var.prefix}-cluster-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.default.id
}

resource "google_compute_firewall" "default" {
  name    = "${var.prefix}-redpanda-firewall"
  network = google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = ["9092", "8082", "8081", "9644", "33145"]
  }
  source_ranges = ["10.0.0.0/24"]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.prefix}-allow-ssh"
  network = google_compute_network.default.name

  direction = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["allow-ssh"]
}

resource "google_compute_firewall" "http" {
  name    = "${var.prefix}-main-network-allow-http"
  network = google_compute_network.default.name

  direction = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
}

resource "google_compute_router" "nat_router" {
  name    = "${var.prefix}-redpanda-nat-router"
  region  = var.region
  network = google_compute_network.default.id
}

resource "google_compute_router_nat" "nat_config" {
  name                              = "${var.prefix}-redpanda-nat-config"
  router                            = google_compute_router.nat_router.name
  region                            = var.region
  nat_ip_allocate_option            = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
