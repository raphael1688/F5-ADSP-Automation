locals {
  infra = data.terraform_remote_state.infra.outputs

  project_prefix = local.infra.project_prefix
  resource_owner = local.infra.resource_owner
  build_suffix   = local.infra.build_suffix
  gcp_region     = local.infra.gcp_region

  # Network wiring from infra outputs
  network_id    = data.terraform_remote_state.infra.outputs.vpc_network_id
  # Prefer app subnet; fall back to internal then external then mgmt
  subnetwork_id = try(
    data.terraform_remote_state.infra.outputs.app_subnet_id,
    data.terraform_remote_state.infra.outputs.int_subnet_id,
    data.terraform_remote_state.infra.outputs.ext_subnet_id,
    data.terraform_remote_state.infra.outputs.mgmt_subnet_id
  )

  # Firewall tag to attach to this instance (internal by default)
  instance_network_tags = distinct(compact([
    try(data.terraform_remote_state.infra.outputs.tag_int, ""),
    var.additional_network_tag
  ]))

  # SSH keys: always include generated key; append external key if provided
  ssh_keys_metadata = join("\n", compact([
    "adminuser:${tls_private_key.vm_ssh_key.public_key_openssh}",
    var.ssh_pub != "" ? "adminuser:${var.ssh_pub}" : "",
  ]))

  juice_shop_startup_script = <<-EOF
    #!/bin/bash
    set -e
    cat <<SERVICE > /etc/systemd/system/juice-shop.service
[Unit]
Description=OWASP Juice Shop
Requires=docker.service
After=docker.service

[Service]
Restart=on-failure
ExecStartPre=-/usr/bin/docker rm -f juice-shop
ExecStart=/usr/bin/docker run --rm --name juice-shop -p 80:3000 bkimminich/juice-shop:latest
ExecStop=/usr/bin/docker stop juice-shop

[Install]
WantedBy=multi-user.target
SERVICE

    systemctl daemon-reload
    systemctl enable --now juice-shop.service
  EOF

  crapi_startup_script = <<-EOF
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

  comfy_startup_script = <<-EOF
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

  docker_apps = {
    for name, cfg in {
      juice-shop = {
        enabled                 = var.vm_create_juice_shop
        metadata_startup_script = local.juice_shop_startup_script
      }
      crapi = {
        enabled                 = var.vm_create_crapi
        metadata_startup_script = local.crapi_startup_script
      }
      comfy-capybara = {
        enabled                 = var.vm_create_comfy_capybara
        metadata_startup_script = local.comfy_startup_script
      }
    } : name => cfg if cfg.enabled
  }
}
