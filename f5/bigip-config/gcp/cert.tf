resource "tls_private_key" "front_door" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "front_door" {
  private_key_pem = tls_private_key.front_door.private_key_pem

  subject {
    common_name = var.self_signed_cert_cn
  }

  validity_period_hours = var.self_signed_cert_validity_hours
  early_renewal_hours   = 720

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}
