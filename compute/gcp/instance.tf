# Any zone up within the region
data "google_compute_zones" "available" {
  status = "UP"
}

# Stable Container-Optimized OS Image
data "google_compute_image" "cos" {
  family  = "cos-stable"
  project = "cos-cloud"
}

# Generated SSH key
resource "tls_private_key" "vm_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Docker host VM (generic compute) - one shared shape for every app in
# local.docker_apps, so a field added/fixed here reaches all of them.
resource "google_compute_instance" "docker_host" {
  for_each = local.docker_apps

  name                      = "${local.project_prefix}-${each.key}-docker-host-${local.build_suffix}"
  machine_type              = var.machine_type
  zone                      = data.google_compute_zones.available.names[0]
  allow_stopping_for_update = true

  tags = concat(local.instance_network_tags, ["${local.project_prefix}-mgmt"])

  boot_disk {
    initialize_params {
      image = data.google_compute_image.cos.self_link
      size  = var.boot_disk_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = local.subnetwork_id

    dynamic "access_config" {
      for_each = var.assign_public_ip ? [1] : []
      content {}
    }
  }

  service_account {
    email  = var.gcp_runtime_service_account_email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = {
    ssh-keys       = local.ssh_keys_metadata
    enable-oslogin = var.enable_oslogin ? "TRUE" : "FALSE"
  }

  metadata_startup_script = each.value.metadata_startup_script

  labels = {
    name  = "${local.project_prefix}-docker-host"
    owner = local.resource_owner
  }
}

# Preserve existing instances across the move to for_each instead of
# destroying and recreating them.
moved {
  from = google_compute_instance.juice_shop[0]
  to   = google_compute_instance.docker_host["juice-shop"]
}

moved {
  from = google_compute_instance.crapi[0]
  to   = google_compute_instance.docker_host["crapi"]
}

moved {
  from = google_compute_instance.comfy_capybara[0]
  to   = google_compute_instance.docker_host["comfy-capybara"]
}
