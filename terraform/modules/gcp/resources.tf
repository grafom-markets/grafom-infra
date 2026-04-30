# ---------------------------------------------------------------------------
# Firewall — 9 TCP rules matching Grafom port layout
# ---------------------------------------------------------------------------

resource "google_compute_firewall" "grafom" {
  name    = "${var.project_name}-${var.environment}-fw"
  network = "default"

  dynamic "allow" {
    for_each = var.open_ports
    content {
      protocol = "tcp"
      ports    = [tostring(allow.value)]
    }
  }

  source_ranges = var.allowed_ips
  target_tags   = ["${var.project_name}-${var.environment}"]
}

# ---------------------------------------------------------------------------
# Static IP — prevents IP change on stop/start
# ---------------------------------------------------------------------------

resource "google_compute_address" "grafom" {
  name   = "${var.project_name}-${var.environment}-ip"
  region = var.region
}

# ---------------------------------------------------------------------------
# Compute instance — e2-micro, Ubuntu 22.04, 30 GB pd-standard (always-free)
# ---------------------------------------------------------------------------

resource "google_compute_instance" "grafom" {
  name         = "${var.project_name}-${var.environment}"
  machine_type = var.instance_type
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 30
      type  = "pd-standard"
    }
  }

  network_interface {
    network = "default"

    access_config {
      nat_ip = google_compute_address.grafom.address
    }
  }

  metadata = {
    ssh-keys = "ubuntu:${file(pathexpand(var.ssh_public_key_path))}"
  }

  tags = ["${var.project_name}-${var.environment}"]

  labels = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "opentofu"
  }
}
