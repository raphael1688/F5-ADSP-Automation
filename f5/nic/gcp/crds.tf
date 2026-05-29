data "kubectl_file_documents" "nic_crds" {
  content = data.http.nic_crds.response_body
}

resource "kubectl_manifest" "nic_crds" {
  for_each = data.kubectl_file_documents.nic_crds.manifests

  yaml_body         = each.value
  server_side_apply = true
  wait              = true
}
