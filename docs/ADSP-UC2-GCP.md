# Deploy Use-Case 2 in Google Cloud

This document provides complete instructions for deploying Application Security and Delivery Portfolio (ADSP) Use-Case 2 in Google Cloud Platform.

---

## Overview

This repository deploys a Kubernetes-based application security demonstration consisting of:

- **Network Infrastructure** - VPC with a dedicated `k8s` subnet (with secondary ranges for pods and services), management subnet, and NAT for private nodes
- **GKE Standard Cluster** - zonal cluster with private nodes, public control plane locked down by authorized networks, Dataplane V2, Workload Identity, shielded nodes
- **F5 NGINX Ingress Controller (NIC)** with **NGINX App Protect V5 (NAP V5)** sidecars (`waf-enforcer`, `waf-config-mgr`)
- **Application Workload** - `comfy-capybara` deployed via the `oci://ghcr.io/knowbase/charts/comfy-capybara` Helm chart, exposed through a NIC `VirtualServer` with the NAP `waf-policy` attached
- **F5 Distributed Cloud (XC)** - HTTPS LoadBalancer with WAF and API protection (validation report, fall-through report) fronting the NIC ingress; origin auto-discovered from the NIC LoadBalancer IP via remote state

The deployment is orchestrated entirely through GitHub Actions using Terraform with GCS remote state. Local execution is not supported.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ F5 Distributed Cloud (XC)                                   │
│ ├─ HTTPS LoadBalancer (auto-cert)                           │
│ ├─ WAF (blocking)                                           │
│ ├─ API Protection (api_definition built from your OAS)      │
│ │  ├─ Validation: active, report mode                       │
│ │  └─ Fall-through: report mode                             │
│ └─ Origin: NIC LoadBalancer Public IP (from NIC state       │
│    via the backend_nic flag)                                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ GCP VPC (${project_prefix}-vpc-*)                           │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ GKE Standard Cluster (zonal, private nodes)          │  │
│  │                                                       │  │
│  │  ┌────────────────────────────────────────────────┐  │  │
│  │  │ Namespace: nginx-ingress                       │  │  │
│  │  │ ├─ NIC Helm release                            │  │  │
│  │  │ │  └─ NAP sidecars: waf-enforcer + config-mgr  │  │  │
│  │  │ ├─ Policy CRD: waf-policy (compiled bundle)    │  │  │
│  │  │ └─ Service type=LoadBalancer (public IP)       │  │  │
│  │  └────────────────────────────────────────────────┘  │  │
│  │                              │                        │  │
│  │                              ▼  (VirtualServer route) │  │
│  │  ┌────────────────────────────────────────────────┐  │  │
│  │  │ Namespace: comfy-capybara                      │  │  │
│  │  │ ├─ Deployments: frontend, api, internal-mock,  │  │  │
│  │  │ │              shadow-api, db                  │  │  │
│  │  │ └─ VirtualServer (refs waf-policy in           │  │  │
│  │  │    nginx-ingress, server-wide + /api)          │  │  │
│  │  └────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  Subnets: mgmt (/24), k8s (/18 + pods/svcs secondary)      │
└─────────────────────────────────────────────────────────────┘
```

### Deployment Flow

The GitHub Actions workflow deploys modules sequentially with dependencies:

```
1. Bootstrap State Bucket (GCS)
   ↓
2. Terraform: Infra (VPC, k8s subnet with secondary ranges, NAT, firewall)
   ↓
3. Terraform: GKE (Standard zonal cluster, private nodes, authorized networks)
   ↓
4. Workflow: Compile NAP policy (waf-compiler 5.4.0 → /tmp/compiled_policy.tgz)
   ↓
5. Terraform: NIC + NAP (Helm release; mounts compiled policy via Secret)
   ↓
6. Terraform: App (helm_release of comfy-capybara; chart emits a NIC VirtualServer)
   ↓
7. Terraform: F5 XC (HTTP LB + WAF + api_definition from your OAS; origin = NIC LB IP)
```

**NAP V5 Policy Flow:**
- Policy source lives at `config/uc2/nap/policy.json`
- Workflow runs `private-registry.nginx.com/nap/waf-compiler:5.4.0` to produce `/tmp/compiled_policy.tgz`
- Terraform mounts the compiled bundle into a Kubernetes Secret and exposes it via the chart's `extraVolumes` mechanism
- The `waf-config-mgr` sidecar watches for the bundle and pushes it to the `waf-enforcer` sidecar
- The `Policy` CRD (`waf-policy`) in the `nginx-ingress` namespace is what application `VirtualServer` resources reference

**API Protection Flow:**
- OpenAPI spec at `config/uc2/app/oas/openapi.json` is base64-encoded by the workflow and passed to the XC module as `xc_oas_content`
- The `volterra_api_definition` resource references it inline (`string:///<base64>`)
- The `volterra_http_loadbalancer` attaches the api_definition with validation active in report mode and fall-through in report mode by default

Destroy operations run in reverse order: `XC → App → NIC → GKE → Infra → State Bucket`

---

## Prerequisites

### GCP Requirements

1. **GCP Project** with billing enabled
2. **Required APIs enabled:**
   - Compute Engine API
   - Kubernetes Engine API
   - Cloud Resource Manager API
   - Cloud Storage API
   - IAM Service Account Credentials API
3. **Service Account** with the following roles:
   - `roles/compute.admin`
   - `roles/container.admin`
   - `roles/storage.admin`
   - `roles/iam.serviceAccountUser`
4. **Workload Identity Pool** configured for GitHub Actions federation
5. **Sufficient Quotas:**
   - CPUs: 8+ (default GKE node pool is 2× `e2-standard-4`)
   - External IP addresses: 2+ (NAT + NIC LoadBalancer)
   - Persistent disk: 100+ GB

#### Hardening: tighter deploy SA IAM (optional)

The roles above are the simplest set that lets the workflow run end-to-end. For least-privilege, replace `roles/compute.admin` and `roles/container.admin` on the deploy SA with the narrower split:

- `roles/compute.networkAdmin` (VPC, subnets, router, NAT)
- `roles/compute.securityAdmin` (firewall rules)
- `roles/container.clusterAdmin` (GKE cluster + node pool CRUD)
- `roles/container.developer` (helm / kubectl into the cluster)

`roles/storage.admin` can be swapped for a custom storage-admin role with `storage.buckets.{create,get,update}` + `storage.objects.{create,get,delete,list}`. Bind `roles/iam.serviceAccountUser` only on the runtime SA attached to GKE nodes, not project-wide.

#### Runtime SA (attached to GKE nodes)

The runtime SA referenced by `k8s.gcp_runtime_service_account_email` in `config/uc2/gcp/env.json` carries the standard GKE node telemetry roles:

- `roles/logging.logWriter`
- `roles/monitoring.metricWriter`
- `roles/monitoring.viewer`
- `roles/stackdriver.resourceMetadata.writer`

### F5 NGINX Plus + NAP V5 Requirements

The NIC + NAP V5 images come from `private-registry.nginx.com`, which requires a valid NGINX Plus subscription:

1. **NGINX JWT Token** - from MyF5 portal, used for chart/image entitlement
2. **NGINX Repository Client Certificate** - `nginx-repo.crt` from the subscription bundle
3. **NGINX Repository Client Key** - `nginx-repo.key` from the subscription bundle

### F5 Distributed Cloud (XC) Requirements

1. **XC Tenant** with API access enabled
2. **API Certificate** (.p12 file) with password
3. **Namespace** - automatically created by Terraform
4. **Custom Domain** configured for `app_domain` (XC also supports tenant-provided domains)

### GitHub Repository Requirements

1. **Forked Repository** with Actions enabled
2. **Protected Branches:**
   - `deploy-adsp-uc2` - triggers validation + deployment
   - `test-adsp-uc2` - triggers validation only
   - `destroy-adsp-uc2` - triggers destroy workflow

### GitHub Secrets Setup

Configure the following secrets in GitHub repository settings: `Settings → Secrets and variables → Actions → New repository secret`

#### Required Secrets

| Secret Name | Description | How to Obtain |
|-------------|-------------|---------------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Workload Identity Provider resource name | Format: `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_ID/providers/PROVIDER_ID` |
| `GCP_SERVICE_ACCOUNT` | Deploy service account email | Format: `SERVICE_ACCOUNT_NAME@PROJECT_ID.iam.gserviceaccount.com` |
| `NGINX_JWT` | NGINX Plus entitlement JWT | Download from MyF5 portal under your NGINX Plus subscription |
| `NGINX_REPO_CRT` | Client certificate for `private-registry.nginx.com` | `nginx-repo.crt` contents from NGINX subscription bundle |
| `NGINX_REPO_KEY` | Client key for `private-registry.nginx.com` | `nginx-repo.key` contents from NGINX subscription bundle |
| `VES_P12_CONTENT` | Base64-encoded XC API certificate (.p12 file) | Run: `base64 -w 0 /path/to/certificate.p12` (Linux) or `base64 -i /path/to/certificate.p12` (macOS) |
| `VES_P12_PASSWORD` | Password for XC API certificate | Provided when downloading certificate from XC console |

All secret values are the file contents (PEM body / JWT body / base64 blob), not file paths.

#### Workload Identity Federation Setup

If you need to create the Workload Identity Pool:

```bash
# Set variables
PROJECT_ID="your-project-id"
POOL_NAME="github-actions-pool"
PROVIDER_NAME="github-provider"
SERVICE_ACCOUNT="github-actions-sa@${PROJECT_ID}.iam.gserviceaccount.com"
REPO="your-github-org/your-repo"

# Create Workload Identity Pool
gcloud iam workload-identity-pools create "${POOL_NAME}" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --display-name="GitHub Actions Pool"

# Create Provider
gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_NAME}" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="${POOL_NAME}" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Grant service account access
gcloud iam service-accounts add-iam-policy-binding "${SERVICE_ACCOUNT}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/${POOL_NAME}/attribute.repository/${REPO}"
```

---

## Quickstart

The minimum edits to get UC2 running, assuming you already have GCP + WIF + F5 entitlements wired up per the Prerequisites section above.

### `config/common/gcp/env.json`

```json
{
  "gcp_project_id": "<your-project-id>",
  "gcp_region": "us-west1",
  "gcp_zone": "us-west1-a",
  "project_prefix": "<short-prefix>",
  "resource_owner": "<initials>",
  "admin_src_addr": ["1.2.3.4/32", "10.0.0.0/8"],
  "tf_state_bucket": ""
}
```

- `admin_src_addr` is a JSON array of **quoted CIDR strings** (`IP/prefix`). Bare IPs and unquoted values fail JSON parsing in the workflow.
- Leave `tf_state_bucket` empty; the workflow derives it as `<project_prefix>-state-bucket`.

### `config/uc2/gcp/env.json`

```json
{
  "k8s": {
    "gcp_runtime_service_account_email": "<runtime-sa>@<project-id>.iam.gserviceaccount.com"
  }
}
```

The runtime SA email is the one attached to GKE nodes. Every other field keeps its example default.

### `config/uc2/app/env.json`

```json
{
  "app": {
    "app_host": "<fqdn-served-by-NIC-and-XC>"
  }
}
```

`app_host` must equal `xc_base.app_domain` below.

### `config/uc2/xc/env.json`

```json
{
  "xc_base": {
    "xc_tenant": "<your-tenant>",
    "api_url": "https://<your-tenant>.console.ves.volterra.io/api",
    "xc_namespace": "<xc-namespace>",
    "app_domain": "<fqdn>"
  }
}
```

`xc_namespace` cannot be `system` or `shared`. `app_domain` must equal `app.app_host`.

### `config/uc2/app/oas/openapi.json`

Drop the OpenAPI spec for the app at `config/uc2/app/oas/openapi.json` (or `openapi.yaml` / `openapi.yml`). The workflow base64-encodes it and feeds it into the XC API definition inline. If the file is missing the XC job fails with a clear message.

### Deploy

```bash
git checkout -b deploy-adsp-uc2 && git push -u origin deploy-adsp-uc2
```

Watch the workflow in the Actions tab. Modules run: state bucket → infra → GKE → NIC+NAP → app → XC.

`test-adsp-uc2` runs validate only. `destroy-adsp-uc2` tears down in reverse order.

---

## Repository Structure

```
F5-ADSP-Automation/
├── .github/workflows/
│   ├── deploy-adsp-uc2-gcp.yml      # Main deployment workflow
│   ├── destroy-adsp-uc2-gcp.yml     # Destroy workflow
│   └── pr_tf_validate.yml           # PR validation
├── config/
│   ├── common/
│   │   └── gcp/env.json             # Shared GCP settings
│   └── uc2/
│       ├── gcp/env.json             # UC2 GCP + GKE + NIC config
│       ├── nap/policy.json          # NAP policy source (compiled in workflow)
│       ├── app/
│       │   ├── env.json             # comfy-capybara chart + VirtualServer config
│       │   └── oas/openapi.json     # OpenAPI spec for the app (you drop this)
│       └── xc/env.json              # XC tenant + LoadBalancer + WAF/API feature flags
├── infra/gcp/                       # Network infrastructure
├── k8s/gcp/                         # GKE Standard cluster
├── f5/
│   ├── nic/gcp/                     # NIC + NAP V5 helm release
│   └── xc/                          # F5 Distributed Cloud (shared module)
├── app/gcp/                         # comfy-capybara helm_release + VirtualServer
└── docs/
    └── ADSP-UC2-GCP.md              # This document
```

### Terraform State Layout

Remote state is stored in GCS bucket `${project_prefix}-state-bucket`:

- `state/uc2/infra/` - VPC, subnets, firewall rules
- `state/uc2/k8s/` - GKE cluster + node pool
- `state/uc2/nic/` - NIC + NAP Helm release, Secrets, CRDs
- `state/uc2/app/` - comfy-capybara Helm release, namespace
- `state/uc2/xc/` - XC namespace, HTTP LoadBalancer, WAF policy, api_definition
- `artifacts/uc2/` - compiled NAP policy + base64-encoded OAS (uploaded by workflow)

---

## Configuration

### Step 1: Configure Common Settings

Edit `config/common/gcp/env.json`:

```json
{
  "gcp_project_id": "your-gcp-project-id",
  "gcp_region": "us-west1",
  "gcp_zone": "us-west1-a",
  "project_prefix": "your-prefix",
  "resource_owner": "your-initials",
  "admin_src_addr": ["1.2.3.4/32", "10.0.0.0/8"],
  "tf_state_bucket": ""
}
```

**Required Changes:**
- `gcp_project_id` - Your GCP project ID
- `gcp_region` - Target GCP region
- `gcp_zone` - Target GCP zone (must be inside `gcp_region`; GKE cluster is zonal)
- `project_prefix` - Unique prefix for resource naming (lowercase, alphanumeric)
- `resource_owner` - Your initials or identifier for resource tagging
- `admin_src_addr` - Public IP CIDRs allowed to reach management interfaces and the GKE control plane. Each entry is a quoted CIDR (`/32` for a single host); bare IPs and unquoted values fail JSON parsing.

**Leave as-is:**
- `tf_state_bucket` - auto-generated as `${project_prefix}-state-bucket`

### Step 2: Configure Use-Case Settings

Edit `config/uc2/gcp/env.json`:

```json
{
  "features": {
    "gke": true,
    "nic": true
  },
  "k8s": {
    "gcp_runtime_service_account_email": "<runtime-sa>@<project-id>.iam.gserviceaccount.com",
    "release_channel": "REGULAR",
    "node_machine_type": "e2-standard-4",
    "node_count": 2,
    "node_disk_size_gb": 50,
    "node_disk_type": "pd-balanced",
    "master_ipv4_cidr_block": "172.16.0.0/28",
    "master_authorized_networks_extra": []
  },
  "nic": {
    "namespace": "nginx-ingress",
    "chart_version": "2.0.1",
    "nic_image_repository": "private-registry.nginx.com/nginx-ic-nap-v5/nginx-plus-ingress",
    "nic_image_tag": "4.0.1",
    "nap_enforcer_image": "private-registry.nginx.com/nap/waf-enforcer",
    "nap_enforcer_tag": "5.4.0",
    "nap_config_mgr_image": "private-registry.nginx.com/nap/waf-config-mgr",
    "nap_config_mgr_tag": "5.4.0",
    "nic_crds_url": "https://raw.githubusercontent.com/nginx/kubernetes-ingress/v4.0.1/deploy/crds.yaml",
    "waf_policy_name": "waf-policy",
    "nap_policy_payload": "../config/uc2/nap/policy.json"
  }
}
```

**Required Changes:**
- `k8s.gcp_runtime_service_account_email` - Service account attached to GKE nodes

**Customizable Settings (`k8s` block):**
- `release_channel` - `RAPID`, `REGULAR`, or `STABLE`
- `node_machine_type` - GKE node machine type
- `node_count` - number of nodes in the pool
- `node_disk_size_gb` / `node_disk_type` - node boot disk
- `master_ipv4_cidr_block` - control plane private endpoint CIDR (must not overlap with subnets)
- `master_authorized_networks_extra` - additional CIDRs allowed to reach the control plane on top of `admin_src_addr`

**Customizable Settings (`nic` block):**
- `chart_version` / `nic_image_tag` - pin specific NIC versions
- `nap_enforcer_tag` / `nap_config_mgr_tag` - pin NAP V5 sidecar versions (must match `waf-compiler` tag used in the workflow)
- `nic_crds_url` - pin CRD source to a specific NIC release (must match `nic_image_tag`)
- `waf_policy_name` - name of the `Policy` CRD that apps reference from their `VirtualServer`

**Do Not Modify:**
- `features.gke: true` / `features.nic: true` - required for UC2

### Step 3: Configure App Settings

Edit `config/uc2/app/env.json`:

```json
{
  "app": {
    "namespace": "comfy-capybara",
    "chart_repository": "oci://ghcr.io/knowbase/charts",
    "chart_name": "comfy-capybara",
    "chart_version": "0.1.0",
    "app_host": "comfy.example.com",
    "image_registry": "",
    "image_tag": "",
    "image_pull_secret_name": "",
    "vs_tls_enabled": false,
    "vs_tls_secret_name": "",
    "attach_waf_server_wide": true,
    "attach_waf_to_api_route": true
  }
}
```

**Required Changes:**
- `app_host` - FQDN exposed by the NIC `VirtualServer`. Must equal `xc_base.app_domain` in Step 6.

**Customizable Settings:**
- `chart_version` - pin a specific chart release published by the comfy-capybara repo
- `image_registry` / `image_tag` - override the chart's defaults if pulling from a fork or non-`appVersion` tag; empty values fall back to chart defaults
- `image_pull_secret_name` - name of a pre-created `Secret` in the app namespace for a private registry
- `vs_tls_enabled` + `vs_tls_secret_name` - terminate TLS at the NIC `VirtualServer`. Defaults off because XC terminates TLS at the edge.
- `attach_waf_server_wide` - attach `waf-policy` at the `VirtualServer` (covers every route as a baseline)
- `attach_waf_to_api_route` - attach `waf-policy` on the `/api` route specifically. Route-level policies override server-wide ones; when both are on with the same policy the behavior is "enforce everywhere".

### Step 4: Configure OpenAPI Spec

Drop the OpenAPI spec for the app at one of:
- `config/uc2/app/oas/openapi.json`
- `config/uc2/app/oas/openapi.yaml`
- `config/uc2/app/oas/openapi.yml`

The workflow base64-encodes the file and feeds it into the XC `volterra_api_definition` resource inline (`swagger_specs = ["string:///<base64>"]`). The XC job fails clearly if the file is missing.

The spec must be valid OpenAPI 3.x. Postman collections and raw Swagger 1.x are not accepted.

### Step 5: Configure NAP Policy

Edit `config/uc2/nap/policy.json`. The default is a baseline blocking policy on the NGINX template:

```json
{
  "policy": {
    "name": "uc2-baseline",
    "template": { "name": "POLICY_TEMPLATE_NGINX_BASE" },
    "applicationLanguage": "utf-8",
    "enforcementMode": "blocking"
  }
}
```

The workflow runs `private-registry.nginx.com/nap/waf-compiler:5.4.0` against this file to produce `/tmp/compiled_policy.tgz`. Any policy JSON the compiler accepts is valid; if you change the compiler tag, change the NAP sidecar tags in `config/uc2/gcp/env.json` to match.

### Step 6: Configure F5 XC Settings

Edit `config/uc2/xc/env.json`:

```json
{
  "xc_base": {
    "xc_tenant": "your-xc-tenant",
    "api_url": "https://your-tenant.console.ves.volterra.io/api",
    "xc_namespace": "your-namespace",
    "app_domain": "your-app.example.com",
    "origin_server": "",
    "origin_port": "80",
    "backend_bigip": false,
    "backend_nic": true,
    "xc_waf_blocking": true
  },
  "xc_features": {
    "xc_api_pro": true,
    "xc_api_val": true,
    "xc_api_val_all": true,
    "xc_api_val_active": true,
    "enforcement_report": true,
    "fall_through_mode_report": true
  }
}
```

**Required Changes:**
- `xc_tenant` - Your XC tenant name
- `api_url` - Your XC API URL
- `xc_namespace` - Desired namespace name (cannot be `system` or `shared`)
- `app_domain` - Public domain XC will serve. Must equal `app.app_host` in Step 3.

**Important:**
- `backend_nic: true` - XC origin pool resolves the NIC LoadBalancer IP from `state/uc2/nic` via remote state.
- `origin_server: ""` - leave empty; resolved automatically from NIC remote state.
- `xc_api_pro: true` + `xc_api_val_*` + `enforcement_report: true` + `fall_through_mode_report: true` - default UC2 stance is "report everything API-related; block traditional WAF hits via `xc_waf_blocking: true`". Flip `enforcement_block: true` and `fall_through_mode_report: false` if you want OAS enforcement.
- The full set of feature flags is in [f5/xc/variables.tf](../f5/xc/variables.tf).

---

## Deployment Procedures

### Initial Deployment

1. **Fork this repository** to your GitHub organization or account
2. **Configure files:**
   - `config/common/gcp/env.json`
   - `config/uc2/gcp/env.json`
   - `config/uc2/app/env.json`
   - `config/uc2/app/oas/openapi.json` (or `.yaml` / `.yml`)
   - `config/uc2/nap/policy.json`
   - `config/uc2/xc/env.json`
3. **Set GitHub Secrets** (see GitHub Secrets Setup)
4. **Commit and push changes** to `main` branch
5. **Create deployment branch:**
   ```bash
   git checkout -b deploy-adsp-uc2
   git push origin deploy-adsp-uc2
   ```
6. **Monitor workflow execution** in GitHub Actions tab
7. **Retrieve outputs** (see Accessing Deployment Outputs)

### Validation-Only Testing

To validate Terraform without applying:

```bash
git checkout -b test-adsp-uc2
git push origin test-adsp-uc2
```

This triggers validation for all modules but skips `terraform apply` steps.

### Updating Existing Deployment

1. Make configuration changes on `main` branch
2. Merge or push to `deploy-adsp-uc2` branch
3. Workflow will automatically plan and apply changes

### Destroying Infrastructure

**WARNING:** This permanently deletes all resources including the state bucket.

```bash
git checkout -b destroy-adsp-uc2
git push origin destroy-adsp-uc2
```

Destroy sequence:
1. F5 XC resources (HTTP LB, WAF, namespace)
2. Application workload (comfy-capybara Helm release + namespace)
3. NIC + NAP Helm release
4. GKE cluster
5. Network infrastructure
6. GCS state bucket (including all history)

---

## Accessing Deployment Outputs

### Via GCP Cloud Shell (Recommended)

Activate Cloud Shell in GCP Console, then:

```bash
# Set variables from your config
PROJECT_PREFIX="your-prefix"
STATE_BUCKET="${PROJECT_PREFIX}-state-bucket"

# Get GKE cluster name
gsutil cat gs://${STATE_BUCKET}/state/uc2/k8s/default.tfstate | \
  jq -r '.outputs.cluster_name.value'

# Get NIC LoadBalancer public IP (XC origin)
gsutil cat gs://${STATE_BUCKET}/state/uc2/nic/default.tfstate | \
  jq -r '.outputs.nic_external_ip.value'

# Get NIC namespace + WAF policy
gsutil cat gs://${STATE_BUCKET}/state/uc2/nic/default.tfstate | \
  jq -r '.outputs.nic_namespace.value, .outputs.waf_policy_name.value'

# Get app FQDN + namespace + VirtualServer name
gsutil cat gs://${STATE_BUCKET}/state/uc2/app/default.tfstate | \
  jq -r '.outputs.app_host.value, .outputs.app_namespace.value, .outputs.virtualserver_name.value'

# Get XC public domain + LB name + WAF policy name
gsutil cat gs://${STATE_BUCKET}/state/uc2/xc/default.tfstate | \
  jq -r '.outputs.endpoint.value, .outputs.xc_lb_name.value, .outputs.xc_waf_name.value'
```

### Connect kubectl to the GKE Cluster

```bash
PROJECT_ID="your-gcp-project-id"
ZONE="your-gcp-zone"
CLUSTER_NAME=$(gsutil cat gs://${STATE_BUCKET}/state/uc2/k8s/default.tfstate | \
  jq -r '.outputs.cluster_name.value')

gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --zone="${ZONE}" --project="${PROJECT_ID}"
```

### Key Outputs Reference

| Output | Module | Description |
|--------|--------|-------------|
| `cluster_name` | k8s | GKE cluster name |
| `cluster_endpoint` | k8s | GKE control plane endpoint |
| `nic_namespace` | nic | Namespace hosting NIC and the WAF Policy CRD |
| `nic_external_ip` | nic | NIC LoadBalancer public IP (XC origin) |
| `waf_policy_name` | nic | Policy CRD name apps reference |
| `app_host` | app | FQDN exposed by the NIC `VirtualServer` |
| `app_namespace` | app | Namespace the comfy-capybara workload runs in |
| `virtualserver_name` | app | VirtualServer CRD emitted by the chart |
| `endpoint` | xc | XC application domain (public URL) |
| `xc_lb_name` | xc | XC HTTP LoadBalancer resource name |
| `xc_waf_name` | xc | XC WAF policy resource name |

---

## Verification and Testing

### GKE Cluster Access

```bash
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --zone="${ZONE}" --project="${PROJECT_ID}"

kubectl get nodes
kubectl get ns
```

### NIC + NAP Pod Status

```bash
NIC_NS=$(gsutil cat gs://${STATE_BUCKET}/state/uc2/nic/default.tfstate | \
  jq -r '.outputs.nic_namespace.value')

# Three containers per NIC pod: nginx-ingress, waf-enforcer, waf-config-mgr
kubectl -n "${NIC_NS}" get pods -o wide
kubectl -n "${NIC_NS}" get svc
kubectl -n "${NIC_NS}" get policies

# Tail logs
kubectl -n "${NIC_NS}" logs -l app.kubernetes.io/name=nginx-ingress -c nginx-ingress --tail=100
kubectl -n "${NIC_NS}" logs -l app.kubernetes.io/name=nginx-ingress -c waf-config-mgr --tail=100
kubectl -n "${NIC_NS}" logs -l app.kubernetes.io/name=nginx-ingress -c waf-enforcer  --tail=100
```

### Application Workload Status

```bash
APP_NS=$(gsutil cat gs://${STATE_BUCKET}/state/uc2/app/default.tfstate | \
  jq -r '.outputs.app_namespace.value')

kubectl -n "${APP_NS}" get pods
kubectl -n "${APP_NS}" get svc
kubectl -n "${APP_NS}" get virtualservers
kubectl -n "${APP_NS}" describe virtualserver
```

### Application Reachability

```bash
NIC_IP=$(gsutil cat gs://${STATE_BUCKET}/state/uc2/nic/default.tfstate | \
  jq -r '.outputs.nic_external_ip.value')
APP_HOST=$(gsutil cat gs://${STATE_BUCKET}/state/uc2/app/default.tfstate | \
  jq -r '.outputs.app_host.value')

# Through NIC LoadBalancer directly (Host header drives VirtualServer match)
curl -H "Host: ${APP_HOST}" "http://${NIC_IP}/"
curl -H "Host: ${APP_HOST}" "http://${NIC_IP}/api/healthz"

# Through XC (public domain)
curl "https://${APP_HOST}/"
curl "https://${APP_HOST}/api/healthz"
```

Without a matching `Host` header NIC returns 404; that's expected.

### NAP Policy Enforcement Smoke Test

With `attach_waf_server_wide=true` (default), a SQLi-style probe should be blocked at NIC by NAP:

```bash
curl -i -H "Host: ${APP_HOST}" "http://${NIC_IP}/api/users?id=1%20OR%201=1"

# Tail enforcer logs live
kubectl -n "${NIC_NS}" logs -l app.kubernetes.io/name=nginx-ingress -c waf-enforcer --tail=50 -f
```

XC WAF blocks the same probe at the edge in blocking mode:

```bash
curl -i "https://${APP_HOST}/api/users?id=1%20OR%201=1"
```

### XC LoadBalancer + WAF + API Verification

1. Login to XC Console: `https://your-tenant.console.ves.volterra.io`
2. Verify the namespace exists: `Administration → Namespaces`
3. Navigate to: `Multi-Cloud App Connect → HTTP Load Balancers` in the configured namespace
4. The LoadBalancer should show:
   - **Domain** matching `app_domain` (and the `endpoint` output)
   - **Origin Pool** with one origin server matching the NIC LoadBalancer public IP
   - **WAF** attached, in blocking or monitoring mode per `xc_waf_blocking`
   - **API Definition** attached with active validation in report mode
5. Send live traffic and check `Security → Security Events` for WAF activity, validation reports, and fall-through reports.

---

## Troubleshooting

### GCP Authentication Failures

**Error:** `Error: google: could not find default credentials`

**Resolution:**
- Verify `GCP_WORKLOAD_IDENTITY_PROVIDER` secret is correctly formatted
- Verify `GCP_SERVICE_ACCOUNT` secret matches the service account with WIF binding
- Ensure service account has required roles in GCP project
- Check Workload Identity Pool configuration allows repository access

**Error:** `403 Forbidden` during Terraform operations

**Resolution:**
- Verify service account has `roles/compute.admin`, `roles/container.admin`, and `roles/storage.admin`
- Check API enablement: `gcloud services list --enabled --project=PROJECT_ID`
- Ensure project billing is active

### Service Account `actAs` Errors

**Error:** `The user does not have access to service account <runtime-sa>`

**Resolution:**
- The deploy SA needs `roles/iam.serviceAccountUser` on the runtime SA email set in `config/uc2/gcp/env.json` (`k8s.gcp_runtime_service_account_email`)
- Bind on the runtime SA only, not project-wide

### Remote State Errors

**Error:** `Error: Failed to get existing workspaces: storage: bucket doesn't exist`

**Resolution:**
- State bucket is auto-created by `bootstrap_state_bucket` job
- Verify job completed successfully in Actions log
- Check bucket exists: `gsutil ls -p PROJECT_ID | grep state-bucket`
- Ensure service account has `roles/storage.admin`

**Error:** `Error acquiring the state lock`

**Resolution:**
- Another workflow run may be in progress
- Wait for concurrent run to complete
- If stuck, manually remove lock:
  ```bash
  gsutil ls gs://${STATE_BUCKET}/state/uc2/MODULE_NAME/default.tflock
  gsutil rm gs://${STATE_BUCKET}/state/uc2/MODULE_NAME/default.tflock
  ```

### Configuration Errors

**Error:** `jq: parse error: Invalid numeric literal` in the infra job

**Resolution:**
- Your `admin_src_addr` (or another CIDR/list field) has unquoted values
- JSON requires `["1.2.3.4/32"]`, not `[1.2.3.4/32]`

**Error:** XC job fails with `No OAS spec found at config/uc2/app/oas/...`

**Resolution:**
- Drop your OpenAPI spec at `config/uc2/app/oas/openapi.json` (or `.yaml` / `.yml`) and re-run

### GKE Control Plane Unreachable

**Error:** `Error: Get "https://...": dial tcp ...:443: i/o timeout` during NIC apply

**Resolution:**
- GKE control plane is private; the runner reaches it via authorized networks
- Confirm `admin_src_addr` in `config/common/gcp/env.json` includes the runner's egress IPs, or use `master_authorized_networks_extra` in `config/uc2/gcp/env.json` to add GitHub Actions hosted-runner egress ranges

### NIC Pods CrashLoopBackOff (Image Pull)

**Error:** `ErrImagePull` or `ImagePullBackOff` on NIC or NAP sidecar containers

**Resolution:**
- The `NGINX_REPO_CRT` / `NGINX_REPO_KEY` secrets must match the certificate associated with your active NGINX Plus subscription
- Verify the docker certs install step succeeded in the workflow log
- Sanity-check the secret content has no truncation or extra whitespace
- Confirm `nic_image_tag` and NAP sidecar tags exist at `private-registry.nginx.com`

### NAP Compiler Failures

**Error:** Workflow step `Compile NAP policy` exits non-zero

**Resolution:**
- The compiler image (`private-registry.nginx.com/nap/waf-compiler:5.4.0`) requires the same docker cert install that NIC images use
- Run the compiler locally with the same policy.json to surface the schema error:
  ```bash
  docker run --rm \
    -v "$(pwd)/config/uc2/nap:/policy:ro" \
    -v "$(pwd):/output" \
    private-registry.nginx.com/nap/waf-compiler:5.4.0 \
    -p /policy/policy.json -o /output/compiled_policy.tgz
  ```
- The compiler version (`5.4.0`) must match `nap_enforcer_tag` and `nap_config_mgr_tag` in `config/uc2/gcp/env.json`

### Application Pod Issues

**Error:** `ImagePullBackOff` on `comfy-capybara-*` pods

**Resolution:**
- Images default to `ghcr.io/knowbase/comfy-capybara-{api,internal-mock,shadow-api,frontend}:<chart appVersion>`. If you forked the comfy-capybara repo, set `image_registry` in `config/uc2/app/env.json` to your fork's GHCR namespace.
- Private images need `image_pull_secret_name` to point at a pre-created `Secret` in the app namespace.

**Error:** `VirtualServer` shows `Policy not found` or NAP isn't enforcing

**Resolution:**
- The chart's VirtualServer references `waf-policy` cross-namespace in `nginx-ingress`. Confirm `kubectl -n nginx-ingress get policies` shows the policy.
- If both `attach_waf_server_wide` and `attach_waf_to_api_route` are false, the VirtualServer ships without policy refs; flip at least one to `true`.

### NIC LoadBalancer Pending External IP

**Error:** `kubectl get svc -n nginx-ingress` shows `EXTERNAL-IP: <pending>` for minutes

**Resolution:**
- GKE provisions the LoadBalancer via a target pool; confirm the node pool is healthy: `kubectl get nodes`
- Check GCP regional quota for forwarding rules
- Inspect Service events: `kubectl -n nginx-ingress describe svc`

### XC Provider Errors

**Error:** `Error: error reading VES_P12_PASSWORD`

**Resolution:**
- Verify `VES_P12_PASSWORD` secret is set in GitHub
- Verify password matches the certificate
- Re-download certificate from XC console if expired

**Error:** `Error: Failed to create Volterra API client`

**Resolution:**
- Verify `VES_P12_CONTENT` is correctly base64-encoded
- Test decoding: `echo $VES_P12_CONTENT | base64 -d > test.p12`
- Verify `api_url` in `config/uc2/xc/env.json` matches the tenant
- Check API certificate is not expired in XC console

### XC Origin Shows Down / 502 from Public URL

**Resolution:**
- Confirm `backend_nic: true` is set in `config/uc2/xc/env.json` so XC picks up the NIC IP from `state/uc2/nic`.
- Confirm the NIC LoadBalancer Service has an external IP (see [NIC LoadBalancer Pending External IP](#nic-loadbalancer-pending-external-ip)).
- The `app_domain` in `config/uc2/xc/env.json` must equal the `app_host` in `config/uc2/app/env.json`. If they drift, XC forwards a Host header NIC's `VirtualServer` won't match and the origin looks healthy while the app is unreachable through XC.
- Direct-to-NIC reachability must work before XC will look healthy.

### XC API Definition Apply Fails

**Resolution:**
- Confirm the OAS file under `config/uc2/app/oas/` parses as valid OpenAPI 3.x. Postman collections and raw Swagger 1.x are not accepted.

### Quota Exceeded Errors

**Error:** `Quota 'CPUS' exceeded. Limit: X in region Y`

**Resolution:**
- Request quota increase in GCP Console: `IAM & Admin → Quotas`
- Reduce `node_machine_type` or `node_count` in `config/uc2/gcp/env.json`

---

## Best Practices for Forkers

### Security

- **Never commit secrets** to the repository
- **Use GitHub Secrets** for all sensitive values (passwords, certificates, API keys)
- **Rotate credentials regularly** (XC certificates, NGINX JWT, service account keys)
- **Restrict `admin_src_addr`** to known IP addresses only
- **Enable branch protection** on `deploy-*` and `destroy-*` branches
- **Review firewall rules** before deployment in production environments

### Configuration Management

- **Keep `env.json` files non-secret** - they should contain no credentials
- **Use meaningful `project_prefix`** values to avoid naming collisions
- **Tag resources** using `resource_owner` for cost tracking
- **Version control all changes** to configuration files
- **Test changes** on `test-adsp-uc2` branch before deploying

### State Management

- **Do not edit state files manually**
- **Enable versioning** on state bucket (auto-enabled by workflow)
- **Back up state** before major changes:
  ```bash
  gsutil -m cp -r gs://${STATE_BUCKET}/state/uc2 gs://backup-bucket/state-uc2-$(date +%Y%m%d)
  ```
- **Clean up old state** after successful destroys

### Cost Optimization

- **Destroy environments when not in use** (demo/test scenarios)
- **Use minimal instance sizes** for non-production:
  - GKE nodes: `e2-standard-2` if the workload fits
  - Drop to a single node for capability demos
- **Monitor costs** using GCP Billing Reports
- **Set billing alerts** to avoid unexpected charges

### Workflow Management

- **Use descriptive commit messages** when triggering deployments
- **Monitor GitHub Actions logs** during deployment
- **Review Terraform plans** before approving apply steps
- **Document customizations** in repository README or wiki
- **Test destroy workflow** in non-production before using in production

### Naming Conventions

- **project_prefix:** Lowercase, alphanumeric, max 10 characters
- **resource_owner:** 2-4 character initials or identifier
- **Branch names:** Follow existing pattern (`deploy-`, `test-`, `destroy-`)
- **xc_namespace:** Unique name, cannot be `system` or `shared` (enforced by Terraform validation)

---

## Cost Estimates

Estimated monthly costs for `us-west1` region (as of 2026, defaults from `config/uc2/gcp/env.example.json`):

| Component | Instance Type | Hours/Month | Est. Cost/Month |
|-----------|---------------|-------------|-----------------|
| GKE Standard cluster management | - | 730 | ~$73 (one free cluster per billing account) |
| Node pool (2× e2-standard-4) | e2-standard-4 | 730 | ~$200 |
| Node boot disks (2× 50 GB pd-balanced) | pd-balanced | 730 | ~$10 |
| Cloud NAT | - | 730 | ~$33 |
| External IPs (NAT + NIC LB) | Standard | 730 | ~$15 |
| Network Egress | Variable | - | ~$10 |
| **Total (GCP)** | | | **~$340/month** |
| F5 NGINX Plus + NAP V5 | - | - | Contact F5 Sales |
| F5 Distributed Cloud | - | - | Contact F5 Sales |

**Cost Reduction Options:**
- Destroy infrastructure when not in use (demo environments)
- Reduce `node_count` to 1 for a single-node demo (loses any HA story; fine for capability demos)
- Reduce `node_disk_size_gb` to 30
- Switch `node_machine_type` to `e2-standard-2` if the workload fits

**Note:** F5 pricing varies based on subscription level and contract terms. Contact F5 for detailed pricing.

---

## Additional Resources

### F5 Documentation

- [F5 NGINX Ingress Controller](https://docs.nginx.com/nginx-ingress-controller/)
- [F5 NGINX App Protect V5](https://docs.nginx.com/nginx-app-protect-waf/v5/)
- [NAP Policy Authoring](https://docs.nginx.com/nginx-app-protect-waf/v5/configuration/policy-overview/)
- [F5 Distributed Cloud Documentation](https://docs.cloud.f5.com/)

### GCP Documentation

- [GKE Standard Overview](https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-architecture)
- [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [VPC Networking](https://cloud.google.com/vpc/docs)
- [Private Cluster + Authorized Networks](https://cloud.google.com/kubernetes-engine/docs/concepts/private-cluster-concept)

### Terraform Documentation

- [Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Helm Provider](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)
- [Kubernetes Provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)
- [GCS Backend](https://developer.hashicorp.com/terraform/language/settings/backends/gcs)
- [Remote State Data Source](https://developer.hashicorp.com/terraform/language/state/remote-state-data)

### GitHub Actions

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [google-github-actions/auth](https://github.com/google-github-actions/auth)
- [hashicorp/setup-terraform](https://github.com/hashicorp/setup-terraform)

---

## Support and Contributions

This repository is maintained as a demonstration environment. For issues:

1. **Check Troubleshooting section** above
2. **Review GitHub Actions logs** for detailed error messages
3. **Verify configuration files** match documented formats
4. **Search existing issues** in repository

For questions about F5 products, consult official F5 documentation or contact F5 support.

---

## License

This project uses F5 NGINX Plus + NAP V5 (subscription-based) and F5 Distributed Cloud services (separate billing). Review F5 licensing terms before deployment.

Terraform modules and configuration are provided as-is for demonstration purposes.
