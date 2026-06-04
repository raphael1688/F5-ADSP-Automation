resource "google_service_account" "nap_bundle_reader" {
  project      = var.gcp_project_id
  account_id   = format("%s-nap-rdr-%s", local.project_prefix, local.build_suffix)
  display_name = "NAP bundle reader for ${local.release_name}"
}

resource "google_storage_bucket_iam_member" "nap_bundle_reader" {
  bucket = var.tf_state_bucket
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.nap_bundle_reader.email}"
}

resource "google_service_account_iam_member" "nap_bundle_reader_wi" {
  service_account_id = google_service_account.nap_bundle_reader.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[${kubernetes_namespace.nginx_ingress.metadata[0].name}/${local.ksa_name}]"
}
