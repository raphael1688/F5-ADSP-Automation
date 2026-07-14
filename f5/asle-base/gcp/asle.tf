# Generated SSH key
resource "tls_private_key" "vm_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "google_compute_instance" "asle" {
  name                      = "${local.project_prefix}-${local.service_name}-docker-host-${local.build_suffix}"
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
