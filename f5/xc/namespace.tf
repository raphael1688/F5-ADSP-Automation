resource "volterra_namespace" "this" {
  count = var.create_namespace ? 1 : 0
  name  = var.xc_namespace
}