locals {
  infra = data.terraform_remote_state.infra.outputs
  k8s   = data.terraform_remote_state.k8s.outputs

  project_prefix = local.infra.project_prefix
  resource_owner = local.infra.resource_owner
  build_suffix   = local.infra.build_suffix

  cluster_host           = local.k8s.kubernetes_api_server_url
  cluster_ca_certificate = local.k8s.cluster_ca_certificate

  release_name = format("%s-ngf-%s", local.project_prefix, local.build_suffix)
  gateway_name = format("%s-gw-%s", local.project_prefix, local.build_suffix)

  license_secret_name = "nplus-license"
  regcred_secret_name = "nginx-plus-registry-secret"

  # NGF provisions the data plane Service as <gateway-name>-nginx in the Gateway's namespace.
  dataplane_service_name = "${local.gateway_name}-nginx"

  chart_values = templatefile("${path.module}/values.yaml.tftpl", {
    gatewayclass_name           = var.gatewayclass_name
    nginx_plus_image_repository = var.nginx_plus_image_repository
    nginx_plus_image_tag        = var.nginx_plus_image_tag
    regcred_secret_name         = local.regcred_secret_name
    license_secret_name         = local.license_secret_name
  })
}
