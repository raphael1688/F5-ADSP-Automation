# namespace.tf
# Creates the F5 XC namespace before any resources that depend on it

resource "volterra_namespace" "this" {
  name = var.xc_namespace
}
