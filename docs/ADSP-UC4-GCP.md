# Deploy Use-Case 4 in Google Cloud

This document provides complete instructions for deploying Application Security and Delivery Portfolio (ADSP) Use-Case 4 in Google Cloud Platform.

---

## Overview

Use-Case 4 is the Use-Case 2 demonstration with the in-cluster data plane swapped from NGINX Ingress Controller + NGINX App Protect to **NGINX Gateway Fabric (NGF)** on the Kubernetes Gateway API. NAP is not used; WAF and API protection are provided entirely by F5 Distributed Cloud at the edge.

This repository deploys a Kubernetes-based application delivery demonstration consisting of:

- **Network Infrastructure** - VPC with a dedicated `k8s` subnet (with secondary ranges for pods and services), management subnet, and NAT for private nodes
- **GKE Standard Cluster** - zonal cluster with private nodes, public control plane locked down by authorized networks, Dataplane V2, Workload Identity, shielded nodes
- **F5 NGINX Gateway Fabric (NGF)** running **NGINX Plus**, installed via the `oci://ghcr.io/nginx/charts/nginx-gateway-fabric` chart. The control plane provisions an NGINX data plane `Deployment` and a `Service` of type `LoadBalancer` when the `Gateway` is created.
- **Application Workload** - `comfy-capybara` deployed via the `oci://ghcr.io/knowbase/charts/comfy-capybara` Helm chart, exposed through a Gateway API `HTTPRoute` attached to the NGF `Gateway`
- **F5 Distributed Cloud (XC)** - HTTPS LoadBalancer with WAF and API protection (validation report, fall-through report) fronting the NGF data plane; origin auto-discovered from the data plane LoadBalancer IP via remote state

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
│ └─ Origin: NGF data plane LoadBalancer Public IP            │
│    (from NGF state via the backend_k8s_ingress flag)        │
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
│  │  │ Namespace: nginx-gateway                       │  │  │
│  │  │ ├─ NGF control plane (Helm release)            │  │  │
│  │  │ ├─ Gateway (gatewayClassName: nginx)           │  │  │
│  │  │ └─ Provisioned data plane: <gateway>-nginx     │  │  │
│  │  │    Deployment + Service type=LoadBalancer      │  │  │
│  │  └────────────────────────────────────────────────┘  │  │
│  │                              │                        │  │
│  │                              ▼  (HTTPRoute attach)    │  │
│  │  ┌────────────────────────────────────────────────┐  │  │
│  │  │ Namespace: comfy-capybara                      │  │  │
│  │  │ ├─ Deployments: frontend, api, internal-mock,  │  │  │
│  │  │ │              shadow-api, db                  │  │  │
│  │  │ └─ HTTPRoute (parentRef: Gateway in            │  │  │
│  │  │    nginx-gateway; /api → api, / → frontend)    │  │  │
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
4. Terraform: NGF (Gateway API CRDs, NGF control plane Helm release, Gateway)
   ↓
5. Terraform: App (helm_release of comfy-capybara; emits a Gateway API HTTPRoute)
   ↓
6. Terraform: F5 XC (HTTP LB + WAF + api_definition from your OAS; origin = NGF data plane LB IP)
```

**Routing Flow:**
- The NGF `Gateway` (namespace `nginx-gateway`) has a single `http` listener on port 80 with `allowedRoutes.namespaces.from: All`
- Creating the Gateway makes the NGF control plane provision a data plane `Deployment` and a `Service` named `<gateway-name>-nginx` of type `LoadBalancer` in the `nginx-gateway` namespace
- The app `HTTPRoute` (namespace `comfy-capybara`) attaches to that Gateway via `parentRefs` and routes:
  - `/api` → `api` service on `8000`, with a `URLRewrite` filter (`ReplacePrefixMatch: /`) that strips the `/api` prefix before forwarding
  - `/` → `frontend` service on `8080`

**API Protection Flow:**
- OpenAPI spec at `config/uc4/app/oas/openapi.json` is uploaded by the workflow to the XC object store via the stored-objects API and referenced by the `volterra_api_definition` resource
- The `volterra_http_loadbalancer` attaches the api_definition with validation active in report mode and fall-through in report mode by default

Destroy operations run in reverse order: `XC → App → NGF → GKE → Infra → State Bucket`. The infra destroy job sweeps any GKE-managed `k8s-*` / `gke-*` LoadBalancer firewall rules left attached to the VPC before deleting the network.

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
   - External IP addresses: 2+ (NAT + NGF data plane LoadBalancer)
   - Persistent disk: 100+ GB

#### Hardening: tighter deploy SA IAM (optional)

The roles above are the simplest set that lets the workflow run end-to-end. For least-privilege, replace `roles/compute.admin` and `roles/container.admin` on the deploy SA with the narrower split:

- `roles/compute.networkAdmin` (VPC, subnets, router, NAT)
- `roles/compute.securityAdmin` (firewall rules)
- `roles/container.clusterAdmin` (GKE cluster + node pool CRUD)
- `roles/container.developer` (helm / kubectl into the cluster)

`roles/storage.admin` can be swapped for a custom storage-admin role with `storage.buckets.{create,get,update}` + `storage.objects.{create,get,delete,list}`. Bind `roles/iam.serviceAccountUser` only on the runtime SA attached to GKE nodes, not project-wide.

#### Runtime SA (attached to GKE nodes)

The runtime SA referenced by `k8s.gcp_runtime_service_account_email` in `config/uc4/gcp/env.json` is the same SA UC1/UC2 use. It carries:

- `roles/logging.logWriter` (GKE node telemetry)
- `roles/monitoring.metricWriter`
- `roles/monitoring.viewer`
- `roles/stackdriver.resourceMetadata.writer`

UC4 does not mount anything from GCS into the data plane, so no Workload Identity binding for a bundle reader is required.

### F5 NGINX Plus Requirements

The NGF NGINX Plus data plane image comes from `private-registry.nginx.com`, which requires a valid NGINX Plus subscription:

1. **NGINX JWT Token** - from MyF5 portal, used for the license (`nplus-license`) secret and as the registry username
2. **NGINX Repository Client Certificate** - `nginx-repo.crt` from the subscription bundle
3. **NGINX Repository Client Key** - `nginx-repo.key` from the subscription bundle

The cluster pulls the Plus data plane image directly using the `nginx-plus-registry-secret` (dockerconfigjson) that Terraform creates from `NGINX_JWT`; the NGF control plane image is public (`ghcr.io`).

### F5 Distributed Cloud (XC) Requirements

1. **XC Tenant** with API access enabled
2. **API Certificate** (.p12 file) with password
3. **Namespace** - automatically created by Terraform
4. **Custom Domain** configured for `app_domain` (XC also supports tenant-provided domains)

### GitHub Repository Requirements

1. **Forked Repository** with Actions enabled
2. **Protected Branches:**
   - `deploy-adsp-uc4` - triggers validation + deployment
   - `test-adsp-uc4` - triggers validation only
   - `destroy-adsp-uc4` - triggers destroy workflow

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
PROJECT_NUMBER="your-project-number"
POOL_NAME="${PREFIX}-github-actions-pool"
PROVIDER_NAME="github-provider"
SA_PREFIX=""
SA_SUFFIX="github-actions-sa"
SERVICE_ACCOUNT="${SA_PREFIX}-${SA_SUFFIX}@${PROJECT_ID}.iam.gserviceaccount.com"
GH_ORGANIZATION="your-github-org"
GH_REPO="${GH_ORGANIZATION}/your-repo"

# 1. Create the service account
gcloud iam service-accounts create "${SA_PREFIX}-${SA_SUFFIX}" \
    --display-name="${SA_PREFIX} GitHub Actions for ADSP Automation" \
    --project="${PROJECT_ID}"

# 2. Grant the four roles
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/compute.admin"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/container.admin"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/storage.admin"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/iam.serviceAccountUser"

# 3. Create Workload Identity Pool
gcloud iam workload-identity-pools create "${POOL_NAME}" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --display-name="GitHub Actions Pool"

# 4. Create Provider
gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_NAME}" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="${POOL_NAME}" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository_owner == '${GH_ORGANIZATION}'" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# 5. Grant service account access
gcloud iam service-accounts add-iam-policy-binding "${SERVICE_ACCOUNT}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/attribute.repository/${GH_REPO}"
```

---

## Quickstart

The minimum edits to get UC4 running, assuming you already have GCP + WIF + F5 entitlements wired up per the Prerequisites section above.

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

### `config/uc4/gcp/env.json`

```json
{
  "k8s": {
    "gcp_runtime_service_account_email": "<runtime-sa>@<project-id>.iam.gserviceaccount.com"
  }
}
```

The runtime SA email is the one attached to GKE nodes. Every other field keeps its example default.

### `config/uc4/app/env.json`

```json
{
  "app": {
    "app_host": "<fqdn-served-by-NGF-and-XC>"
  }
}
```

`app_host` must equal `xc_base.app_domain` below.

### `config/uc4/xc/env.json`

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

### `config/uc4/app/oas/openapi.json`

Drop the OpenAPI spec for the app at `config/uc4/app/oas/openapi.json` (or `openapi.yaml` / `openapi.yml`). The workflow uploads it to the XC object store and feeds it into the XC API definition. If the file is missing the XC job fails with a clear message.

### Deploy

```bash
git checkout -b deploy-adsp-uc4 && git push -u origin deploy-adsp-uc4
```

Watch the workflow in the Actions tab. Modules run: state bucket → infra → GKE → NGF → app → XC.

`test-adsp-uc4` runs validate only. `destroy-adsp-uc4` tears down in reverse order.

---

## Repository Structure

```
F5-ADSP-Automation/
├── .github/workflows/
│   ├── deploy-adsp-uc4-gcp.yml      # Main deployment workflow
│   ├── destroy-adsp-uc4-gcp.yml     # Destroy workflow
│   └── pr_tf_validate.yml           # PR validation
├── config/
│   ├── common/
│   │   └── gcp/env.json             # Shared GCP settings
│   └── uc4/
│       ├── gcp/env.json             # UC4 GCP + GKE + NGF config
│       ├── app/
│       │   ├── env.json             # comfy-capybara chart + route config
│       │   └── oas/openapi.json     # OpenAPI spec for the app (you drop this)
│       └── xc/env.json              # XC tenant + LoadBalancer + WAF/API feature flags
├── infra/gcp/                       # Network infrastructure
├── k8s/gcp/                         # GKE Standard cluster
├── f5/
│   ├── ngf/gcp/                     # NGINX Gateway Fabric (NGINX Plus) + Gateway
│   └── xc/                          # F5 Distributed Cloud (shared module)
├── app/gcp/                         # comfy-capybara helm_release + HTTPRoute
└── docs/
    └── ADSP-UC4-GCP.md              # This document
```

### Terraform State Layout

Remote state is stored in GCS bucket `${project_prefix}-state-bucket`:

- `state/uc4/infra/` - VPC, subnets, firewall rules
- `state/uc4/k8s/` - GKE cluster + node pool
- `state/uc4/ngf/` - Gateway API CRDs, NGF control plane Helm release, Gateway, secrets
- `state/uc4/app/` - comfy-capybara Helm release, namespace, HTTPRoute
- `state/uc4/xc/` - XC namespace, HTTP LoadBalancer, WAF policy, api_definition

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

Edit `config/uc4/gcp/env.json`:

```json
{
  "features": {
    "gke": true,
    "k8s_ingress": true
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
  "ngf": {
    "namespace": "nginx-gateway",
    "chart_version": "2.6.4",
    "gatewayclass_name": "nginx",
    "nginx_plus_image_repository": "private-registry.nginx.com/nginx-gateway-fabric/nginx-plus",
    "nginx_plus_image_tag": "2.6.4",
    "gateway_api_crds_url": "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml"
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

**Customizable Settings (`ngf` block):**
- `chart_version` / `nginx_plus_image_tag` - pin specific NGF versions (keep them aligned)
- `gateway_api_crds_url` - the upstream Gateway API standard-channel CRDs. The version must match what the chart version supports (NGF 2.6.4 → Gateway API v1.5.1).
- `gatewayclass_name` - the GatewayClass the chart creates and the Gateway references

**Do Not Modify:**
- `features.gke: true` / `features.k8s_ingress: true` - required for UC4. `k8s_ingress` opens the GKE data-plane LoadBalancer ports (80/443) to admin + XC origin ranges.

### Step 3: Configure App Settings

Edit `config/uc4/app/env.json`:

```json
{
  "app": {
    "namespace": "comfy-capybara",
    "chart_repository": "oci://ghcr.io/knowbase/charts",
    "chart_name": "comfy-capybara",
    "chart_version": "0.4.0",
    "app_host": "comfy.example.com",
    "image_registry": "",
    "image_tag": "",
    "image_pull_secret_name": "",
    "route_type": "httproute"
  }
}
```

**Required Changes:**
- `app_host` - FQDN routed by the `HTTPRoute`. Must equal `xc_base.app_domain` in Step 5.

**Customizable Settings:**
- `chart_version` - pin a specific chart release published by the comfy-capybara repo
- `image_registry` / `image_tag` - override the chart's defaults if pulling from a fork or non-`appVersion` tag; empty values fall back to chart defaults
- `image_pull_secret_name` - name of a pre-created `Secret` in the app namespace for a private registry

**Do Not Modify:**
- `route_type: "httproute"` - selects the Gateway API `HTTPRoute` path of the shared app module. `virtualserver` is the UC2 (NIC) path.

### Step 4: Configure OpenAPI Spec

Drop the OpenAPI spec for the app at one of:
- `config/uc4/app/oas/openapi.json`
- `config/uc4/app/oas/openapi.yaml`
- `config/uc4/app/oas/openapi.yml`

The workflow uploads the file to the XC object store (`stored_objects/swagger/uc4-app-oas`) and references it from the XC `volterra_api_definition`. The XC job fails clearly if the file is missing.

The spec must be valid OpenAPI 3.x. Postman collections and raw Swagger 1.x are not accepted.

### Step 5: Configure F5 XC Settings

Edit `config/uc4/xc/env.json`:

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
    "backend_k8s_ingress": true,
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
- `backend_k8s_ingress: true` - XC origin pool resolves the NGF data plane LoadBalancer IP from `state/uc4/ngf` via remote state.
- `origin_server: ""` - leave empty; resolved automatically from NGF remote state.
- `xc_api_pro: true` + `xc_api_val_*` + `enforcement_report: true` + `fall_through_mode_report: true` - default UC4 stance is "report everything API-related; block traditional WAF hits via `xc_waf_blocking: true`". Flip `enforcement_block: true` and `fall_through_mode_report: false` if you want OAS enforcement.
- The full set of feature flags is in [f5/xc/variables.tf](../f5/xc/variables.tf).

---

## Deployment Procedures

### Initial Deployment

1. **Fork this repository** to your GitHub organization or account
2. **Configure files:**
   - `config/common/gcp/env.json`
   - `config/uc4/gcp/env.json`
   - `config/uc4/app/env.json`
   - `config/uc4/app/oas/openapi.json` (or `.yaml` / `.yml`)
   - `config/uc4/xc/env.json`
3. **Set GitHub Secrets** (see GitHub Secrets Setup)
4. **Commit and push changes** to `main` branch
5. **Create deployment branch:**
   ```bash
   git checkout -b deploy-adsp-uc4
   git push origin deploy-adsp-uc4
   ```
6. **Monitor workflow execution** in GitHub Actions tab
7. **Retrieve outputs** (see Accessing Deployment Outputs)

### Validation-Only Testing

To validate Terraform without applying:

```bash
git checkout -b test-adsp-uc4
git push origin test-adsp-uc4
```

This triggers validation for all modules but skips `terraform apply` steps.

### Updating Existing Deployment

1. Make configuration changes on `main` branch
2. Merge or push to `deploy-adsp-uc4` branch
3. Workflow will automatically plan and apply changes

### Destroying Infrastructure

**WARNING:** This permanently deletes all resources including the state bucket.

```bash
git checkout -b destroy-adsp-uc4
git push origin destroy-adsp-uc4
```

Destroy sequence:
1. F5 XC resources (HTTP LB, WAF, namespace)
2. Application workload (comfy-capybara Helm release + namespace + HTTPRoute)
3. NGF control plane, Gateway, Gateway API CRDs
4. GKE cluster
5. Network infrastructure (after sweeping orphaned GKE LoadBalancer firewall rules)
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
gcloud storage cat gs://${STATE_BUCKET}/state/uc4/k8s/default.tfstate | \
  jq -r '.outputs.cluster_name.value'

# Get NGF data plane LoadBalancer public IP (XC origin)
gcloud storage cat gs://${STATE_BUCKET}/state/uc4/ngf/default.tfstate | \
  jq -r '.outputs.k8s_ingress_external_ip.value'

# Get NGF namespace + Gateway name
gcloud storage cat gs://${STATE_BUCKET}/state/uc4/ngf/default.tfstate | \
  jq -r '.outputs.ngf_namespace.value, .outputs.gateway_name.value'

# Get app FQDN + namespace
gcloud storage cat gs://${STATE_BUCKET}/state/uc4/app/default.tfstate | \
  jq -r '.outputs.app_host.value, .outputs.app_namespace.value'

# Get XC public domain + LB name + WAF policy name
gcloud storage cat gs://${STATE_BUCKET}/state/uc4/xc/default.tfstate | \
  jq -r '.outputs.endpoint.value, .outputs.xc_lb_name.value, .outputs.xc_waf_name.value'
```

### Connect kubectl to the GKE Cluster

```bash
PROJECT_ID="your-gcp-project-id"
ZONE="your-gcp-zone"
CLUSTER_NAME=$(gcloud storage cat gs://${STATE_BUCKET}/state/uc4/k8s/default.tfstate | \
  jq -r '.outputs.cluster_name.value')

gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --zone="${ZONE}" --project="${PROJECT_ID}"
```

### Key Outputs Reference

| Output | Module | Description |
|--------|--------|-------------|
| `cluster_name` | k8s | GKE cluster name |
| `cluster_endpoint` | k8s | GKE control plane endpoint |
| `ngf_namespace` | ngf | Namespace hosting NGF and the Gateway |
| `gateway_name` | ngf | Gateway name (apps reference it from HTTPRoute parentRefs) |
| `k8s_ingress_external_ip` | ngf | NGF data plane LoadBalancer public IP (XC origin) |
| `app_host` | app | FQDN routed by the `HTTPRoute` |
| `app_namespace` | app | Namespace the comfy-capybara workload runs in |
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

### NGF Control Plane + Data Plane Status

```bash
NGF_NS=$(gcloud storage cat gs://${STATE_BUCKET}/state/uc4/ngf/default.tfstate | \
  jq -r '.outputs.ngf_namespace.value')

# Control plane Deployment + provisioned data plane (<gateway>-nginx)
kubectl -n "${NGF_NS}" get pods -o wide
kubectl -n "${NGF_NS}" get svc
kubectl -n "${NGF_NS}" get gateways
kubectl -n "${NGF_NS}" get gatewayclasses

# Gateway should report PROGRAMMED=True and an address
kubectl -n "${NGF_NS}" describe gateway

# Tail control plane logs
kubectl -n "${NGF_NS}" logs -l app.kubernetes.io/name=nginx-gateway-fabric --tail=100
```

### Application Workload Status

```bash
APP_NS=$(gcloud storage cat gs://${STATE_BUCKET}/state/uc4/app/default.tfstate | \
  jq -r '.outputs.app_namespace.value')

kubectl -n "${APP_NS}" get pods
kubectl -n "${APP_NS}" get svc
kubectl -n "${APP_NS}" get httproutes
kubectl -n "${APP_NS}" describe httproute
```

The HTTPRoute should show `Accepted=True` and `ResolvedRefs=True` against the Gateway.

### Application Reachability

```bash
NGF_IP=$(gcloud storage cat gs://${STATE_BUCKET}/state/uc4/ngf/default.tfstate | \
  jq -r '.outputs.k8s_ingress_external_ip.value')
APP_HOST=$(gcloud storage cat gs://${STATE_BUCKET}/state/uc4/app/default.tfstate | \
  jq -r '.outputs.app_host.value')

# Through the NGF data plane LoadBalancer directly (Host header drives HTTPRoute match)
curl -H "Host: ${APP_HOST}" "http://${NGF_IP}/"
curl -H "Host: ${APP_HOST}" "http://${NGF_IP}/api/healthz"

# Through XC (public domain)
curl "https://${APP_HOST}/"
curl "https://${APP_HOST}/api/healthz"
```

Without a matching `Host` header the Gateway returns 404; that's expected.

### XC WAF Smoke Test

UC4 has no in-cluster WAF; protection is provided by XC. With `xc_waf_blocking: true`, XC blocks a SQLi-style probe at the edge:

```bash
curl -i "https://${APP_HOST}/api/users?id=1%20OR%201=1"
```

### XC LoadBalancer + WAF + API Verification

1. Login to XC Console: `https://your-tenant.console.ves.volterra.io`
2. Verify the namespace exists: `Administration → Namespaces`
3. Navigate to: `Multi-Cloud App Connect → HTTP Load Balancers` in the configured namespace
4. The LoadBalancer should show:
   - **Domain** matching `app_domain` (and the `endpoint` output)
   - **Origin Pool** with one origin server matching the NGF data plane LoadBalancer public IP
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
- The deploy SA needs `roles/iam.serviceAccountUser` on the runtime SA email set in `config/uc4/gcp/env.json` (`k8s.gcp_runtime_service_account_email`)
- Bind on the runtime SA only, not project-wide

### Remote State Errors

**Error:** `Error: Failed to get existing workspaces: storage: bucket doesn't exist`

**Resolution:**
- State bucket is auto-created by `bootstrap_state_bucket` job
- Verify job completed successfully in Actions log
- Check bucket exists: `gcloud storage ls -p PROJECT_ID | grep state-bucket`
- Ensure service account has `roles/storage.admin`

**Error:** `Error acquiring the state lock`

**Resolution:**
- Another workflow run may be in progress
- Wait for concurrent run to complete
- If stuck, manually remove lock:
  ```bash
  gcloud storage ls gs://${STATE_BUCKET}/state/uc4/MODULE_NAME/default.tflock
  gcloud storage rm gs://${STATE_BUCKET}/state/uc4/MODULE_NAME/default.tflock
  ```

### Configuration Errors

**Error:** `jq: parse error: Invalid numeric literal` in the infra job

**Resolution:**
- Your `admin_src_addr` (or another CIDR/list field) has unquoted values
- JSON requires `["1.2.3.4/32"]`, not `[1.2.3.4/32]`

**Error:** XC job fails with `No OAS spec found at config/uc4/app/oas/...`

**Resolution:**
- Drop your OpenAPI spec at `config/uc4/app/oas/openapi.json` (or `.yaml` / `.yml`) and re-run

### GKE Control Plane Unreachable

**Error:** `Error: Get "https://...": dial tcp ...:443: i/o timeout` during NGF or App apply

**Resolution:**
- GKE control plane is private; the runner reaches it via authorized networks
- Confirm `admin_src_addr` in `config/common/gcp/env.json` includes the runner's egress IPs, or use `master_authorized_networks_extra` in `config/uc4/gcp/env.json` to add GitHub Actions hosted-runner egress ranges

### NGF Pods CrashLoopBackOff (Image Pull)

**Error:** `ErrImagePull` or `ImagePullBackOff` on the `<gateway>-nginx` data plane pods

**Resolution:**
- The `NGINX_REPO_CRT` / `NGINX_REPO_KEY` / `NGINX_JWT` secrets must match your active NGINX Plus subscription
- Terraform creates `nginx-plus-registry-secret` and `nplus-license` in the `nginx-gateway` namespace from `NGINX_JWT`; confirm they exist: `kubectl -n nginx-gateway get secret`
- Confirm `nginx_plus_image_tag` exists at `private-registry.nginx.com/nginx-gateway-fabric/nginx-plus`

### Gateway Not Programmed / No Address

**Error:** `kubectl -n nginx-gateway describe gateway` shows `PROGRAMMED=False` or no address

**Resolution:**
- Confirm the Gateway API CRDs installed: `kubectl get crd | grep gateway.networking.k8s.io`. The version must match what the chart supports (NGF 2.6.4 → Gateway API v1.5.1, set by `gateway_api_crds_url`).
- Confirm the `nginx` GatewayClass exists and is Accepted: `kubectl get gatewayclass`
- Check control plane logs: `kubectl -n nginx-gateway logs -l app.kubernetes.io/name=nginx-gateway-fabric`

### HTTPRoute Not Attaching

**Error:** `kubectl -n comfy-capybara describe httproute` shows `Accepted=False` (NotAllowedByListeners)

**Resolution:**
- The Gateway listener must allow routes from the app namespace. UC4 sets `allowedRoutes.namespaces.from: All` on the `http` listener; confirm it wasn't overridden.
- Confirm the HTTPRoute `parentRefs` name/namespace/`sectionName: http` match the Gateway. The app module reads these from `state/uc4/ngf`.

### NGF Data Plane LoadBalancer Pending / `k8s_ingress_external_ip` Empty

**Error:** The NGF apply finishes but `k8s_ingress_external_ip` is null, or the XC job reports an empty origin

**Resolution:**
- The data plane Service and its LoadBalancer IP are provisioned asynchronously after the Gateway is accepted. The NGF module waits (`time_sleep` 180s) before reading the Service, but GCP LoadBalancer IP assignment can occasionally exceed that.
- Re-run the `Terraform: NGF` job (push an empty commit to `deploy-adsp-uc4`); on the second pass the Service already has its IP.
- Confirm the Service exists and has an external IP: `kubectl -n nginx-gateway get svc`
- Check GCP regional quota for forwarding rules.

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
- Verify `api_url` in `config/uc4/xc/env.json` matches the tenant
- Check API certificate is not expired in XC console

### XC Origin Shows Down / 502 from Public URL

**Resolution:**
- Confirm `backend_k8s_ingress: true` is set in `config/uc4/xc/env.json` so XC picks up the NGF data plane IP from `state/uc4/ngf`.
- Confirm the data plane Service has an external IP (see the pending-LoadBalancer entry above).
- The `app_domain` in `config/uc4/xc/env.json` must equal the `app_host` in `config/uc4/app/env.json`. If they drift, XC forwards a Host header the `HTTPRoute` won't match and the origin looks healthy while the app is unreachable through XC.
- Direct-to-data-plane reachability must work before XC will look healthy.

### XC API Definition Apply Fails

**Resolution:**
- Confirm the OAS file under `config/uc4/app/oas/` parses as valid OpenAPI 3.x. Postman collections and raw Swagger 1.x are not accepted.

### Quota Exceeded Errors

**Error:** `Quota 'CPUS' exceeded. Limit: X in region Y`

**Resolution:**
- Request quota increase in GCP Console: `IAM & Admin → Quotas`
- Reduce `node_machine_type` or `node_count` in `config/uc4/gcp/env.json`

### VPC Delete Blocked by Orphaned Firewall (destroy)

**Error:** `The network resource '...' is already being used by '.../firewalls/k8s-...-node-http-hc'`

**Resolution:**
- These are GKE-managed LoadBalancer firewall rules left behind when a `LoadBalancer` Service is reaped after the cluster is deleted.
- The infra destroy job sweeps `k8s-*` / `gke-*` firewalls on the VPC before deleting the network. If a run predates that step, re-push `destroy-adsp-uc4` to re-run the infra job.

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
- **Test changes** on `test-adsp-uc4` branch before deploying

### State Management

- **Do not edit state files manually**
- **Enable versioning** on state bucket (auto-enabled by workflow)
- **Back up state** before major changes:
  ```bash
  gcloud storage -m cp -r gs://${STATE_BUCKET}/state/uc4 gs://backup-bucket/state-uc4-$(date +%Y%m%d)
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

Estimated monthly costs for `us-west1` region (as of 2026, defaults from `config/uc4/gcp/env.example.json`):

| Component | Instance Type | Hours/Month | Est. Cost/Month |
|-----------|---------------|-------------|-----------------|
| GKE Standard cluster management | - | 730 | ~$73 (one free cluster per billing account) |
| Node pool (2× e2-standard-4) | e2-standard-4 | 730 | ~$200 |
| Node boot disks (2× 50 GB pd-balanced) | pd-balanced | 730 | ~$10 |
| Cloud NAT | - | 730 | ~$33 |
| External IPs (NAT + NGF data plane LB) | Standard | 730 | ~$15 |
| Network Egress | Variable | - | ~$10 |
| **Total (GCP)** | | | **~$340/month** |
| F5 NGINX Plus | - | - | Contact F5 Sales |
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

- [F5 NGINX Gateway Fabric](https://docs.nginx.com/nginx-gateway-fabric/)
- [NGF Install with NGINX Plus](https://docs.nginx.com/nginx-gateway-fabric/install/nginx-plus/)
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
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

This project uses F5 NGINX Plus (subscription-based) and F5 Distributed Cloud services (separate billing). Review F5 licensing terms before deployment.

Terraform modules and configuration are provided as-is for demonstration purposes.
