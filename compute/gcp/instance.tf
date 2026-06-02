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

resource "google_compute_instance" "comfy_capybara" {
  count = var.vm_create_comfy_capybara ? 1 : 0

  name         = "${local.project_prefix}-${local.comfy.service_name}-docker-host-${local.build_suffix}"
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
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -euo pipefail
    APP_DIR="/var/lib/comfy"
    PLUGIN_DIR="/var/lib/google/cli-plugins"
    mkdir -p $APP_DIR $PLUGIN_DIR

    curl -SL "${var.docker_compose_plugin_url}" -o $PLUGIN_DIR/docker-compose
    chmod +x $PLUGIN_DIR/docker-compose

    docker run --rm -v $APP_DIR:/work -w /work \
      ${var.oras_image} pull \
      ${var.comfy_compose_artifact}:${var.comfy_compose_tag}

    cat <<SERVICE > /etc/systemd/system/comfy.service
[Unit]
Description=Comfy Capybara
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$APP_DIR
Environment="COMFY_TAG=${var.comfy_compose_tag}"
Environment="DOCKER_CONFIG=/var/lib/google"
ExecStart=/usr/bin/docker compose -f docker-compose.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.yml down
Restart=on-failure

[Install]
WantedBy=multi-user.target
SERVICE

    systemctl daemon-reload
    systemctl enable --now comfy.service
  EOF

  labels = {
    name  = "${local.project_prefix}-docker-host"
    owner = local.resource_owner
  }
}

resource "google_compute_instance" "asle" {
  count = var.vm_create_asle ? 1 : 0

  name         = "${local.project_prefix}-${local.asle.service_name}-docker-host-${local.build_suffix}"
  machine_type = var.asle_machine_type
  zone         = data.google_compute_zones.available.names[0]
  allow_stopping_for_update = true

  tags = concat(local.instance_network_tags, ["${local.project_prefix}-mgmt"])

  boot_disk {
    initialize_params {
      image = data.google_compute_image.cos.self_link
      size  = var.asle_boot_disk_gb
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

  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -euo pipefail
    APP_DIR="/var/lib/asle"
    TARBALL="$APP_DIR/image.tar"
    POLLER_DIR="/var/lib/asle-poller"
    mkdir -p $APP_DIR $POLLER_DIR

    gsutil cp "${var.asle_tarball_gcs_uri}" "$TARBALL"
    docker load -i "$TARBALL"
    rm -f "$TARBALL"

    cat <<SERVICE > /etc/systemd/system/asle.service
[Unit]
Description=F5 API Security - Local Edition
Requires=docker.service
After=docker.service

[Service]
Restart=on-failure
ExecStartPre=-/usr/bin/docker rm -f asle
ExecStart=/usr/bin/docker run --rm --name asle \
  -p ${var.asle_management_port}:${var.asle_management_port} \
  -p ${var.asle_telemetry_port}:${var.asle_telemetry_port} \
  ${var.asle_image_ref}
ExecStop=/usr/bin/docker stop asle

[Install]
WantedBy=multi-user.target
SERVICE

    cat <<'POLLER' > $POLLER_DIR/poll.sh
#!/bin/sh
set -eu
GCS_URI="$1"
INTERVAL="$2"

apt-get update -qq && apt-get install -y --no-install-recommends jq curl >/dev/null 2>&1

LAST_GEN=""

while true; do
  CURRENT_GEN=$(gsutil stat "$GCS_URI" 2>/dev/null | awk '/^[ \t]*Generation:/ {print $2}') || CURRENT_GEN=""
  if [ -n "$CURRENT_GEN" ] && [ "$CURRENT_GEN" != "$LAST_GEN" ]; then
    if gsutil cp "$GCS_URI" /tmp/bundle.json 2>/dev/null; then
      OPS_OK=1
      jq -c '.operations[]' /tmp/bundle.json | while IFS= read -r op; do
        METHOD=$(echo "$op" | jq -r '.method')
        PTH=$(echo "$op" | jq -r '.path')
        PAYLOAD=$(echo "$op" | jq -c '.payload')
        if ! curl -sS --fail -X "$METHOD" \
             -H 'Content-Type: application/json' \
             -d "$PAYLOAD" \
             "http://localhost:8000$PTH"; then
          echo "asle-poller: $METHOD $PTH failed; will retry next cycle" >&2
          OPS_OK=0
        fi
      done
      [ "$OPS_OK" = "1" ] && LAST_GEN="$CURRENT_GEN"
    fi
  fi
  sleep "$INTERVAL"
done
POLLER
    chmod +x $POLLER_DIR/poll.sh

    cat <<SERVICE > /etc/systemd/system/asle-poller.service
[Unit]
Description=ASLE config bundle poller
Requires=docker.service asle.service
After=docker.service asle.service

[Service]
Restart=on-failure
ExecStartPre=-/usr/bin/docker rm -f asle-poller
ExecStart=/usr/bin/docker run --rm --name asle-poller --network host \
  -v $POLLER_DIR/poll.sh:/poll.sh:ro \
  ${var.asle_poller_image} \
  /poll.sh "${var.asle_config_bundle_gcs_uri}" "${var.asle_poller_interval_seconds}"
ExecStop=/usr/bin/docker stop asle-poller

[Install]
WantedBy=multi-user.target
SERVICE

    systemctl daemon-reload
    systemctl enable --now asle.service

    if [ -n "${var.asle_config_bundle_gcs_uri}" ]; then
      systemctl enable --now asle-poller.service
    fi
  EOF

  labels = {
    name  = "${local.project_prefix}-docker-host"
    owner = local.resource_owner
  }
}