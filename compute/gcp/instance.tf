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

# Docker host VM (generic compute)
resource "google_compute_instance" "juice_shop" {
  count = var.vm_create_juice_shop ? 1 : 0
  name         = "${local.project_prefix}-${local.juice_shop.service_name}-docker-host-${local.build_suffix}"
  machine_type = var.machine_type
  zone         = data.google_compute_zones.available.names[0]
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

    # Pass variables into the startup script via environment
    # INSTALL_DOCKER_COMPOSE   = var.install_docker_compose ? "true" : "false"
    # EXTRA_STARTUP_SCRIPT_B64 = var.extra_startup_script == "" ? "" : base64encode(var.extra_startup_script)
  }

  metadata_startup_script = "docker run -d -p 80:3000 ${local.juice_shop.image}"

  # metadata_startup_script = <<-EOT
# ${startup}
# EOT

  labels = {
    name  = "${local.project_prefix}-docker-host"
    owner = local.resource_owner
  }
}

resource "google_compute_instance" "crapi" {
  count = var.vm_create_crapi ? 1 : 0
  name         = "${local.project_prefix}-${local.crapi.service_name}-docker-host-${local.build_suffix}"
  machine_type = var.machine_type
  zone         = data.google_compute_zones.available.names[0]
  allow_stopping_for_update = true
  boot_disk {
    initialize_params { image = data.google_compute_image.cos.self_link }
  }

  network_interface {
    subnetwork = local.subnetwork_id

    dynamic "access_config" {
      for_each = var.assign_public_ip ? [1] : []
      content {}
    }
  }

  metadata = { ssh-keys = local.ssh_keys_metadata }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -e
    BIN_DIR="/var/lib/google/bin"
    APP_DIR="/var/lib/crapi"
    mkdir -p $BIN_DIR $APP_DIR
    curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" -o $BIN_DIR/docker-compose
    chmod +x $BIN_DIR/docker-compose
    curl -o $APP_DIR/docker-compose.yml https://raw.githubusercontent.com/OWASP/crAPI/main/deploy/docker/docker-compose.yml
    cat <<SERVICE > /etc/systemd/system/crapi.service
[Unit]
Description=OWASP crAPI Docker Compose Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$APP_DIR
# Start crAPI with compatibility mode for resource limits
Environment="LISTEN_IP=0.0.0.0"
ExecStart=$BIN_DIR/docker-compose -f docker-compose.yml --compatibility up -d
ExecStop=$BIN_DIR/docker-compose -f docker-compose.yml down
Restart=on-failure

[Install]
WantedBy=multi-user.target
SERVICE

    systemctl daemon-reload
    systemctl enable crapi.service
    systemctl start crapi.service
  EOF

  tags = concat(local.instance_network_tags, ["${local.project_prefix}-mgmt"])
}