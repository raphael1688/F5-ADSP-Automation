# Deploy Use-Case 2 in Google Cloud

This document provides complete instructions for deploying Application Security and Delivery Portfolio (ADSP) Use-Case 2 in Google Cloud Platform.

---

## Status

| Block | State |
|-------|-------|
| Bootstrap (GCS state bucket) | Wired |
| Infra (VPC, subnets, NAT) | Wired |
| GKE Standard cluster | Wired |
| NIC + NAP V5 | Wired |
| Application workload | **In progress** — pending Helm chart in the comfy-capybara repo |
| F5 XC (API security) | **Planned** — wired as a follow-up block once app is reachable end-to-end |

The deployable surface today is bootstrap → infra → GKE → NIC+NAP. The app and XC sections below describe the planned final state.

---

## Overview

This repository deploys a Kubernetes-based security demonstration environment consisting of:

- **Network Infrastructure** — VPC with a dedicated `k8s` subnet (with secondary ranges for pods and services), management subnet, and NAT for private nodes
- **GKE Standard Cluster** — zonal, private nodes with a public control plane endpoint locked down via authorized networks, Dataplane V2, Workload Identity, shielded nodes
- **F5 NGINX Ingress Controller (NIC)** with **NGINX App Protect V5 (NAP V5)** sidecars (`waf-enforcer`, `waf-config-mgr`)
- **Application Workload** — `comfy-capybara` deployed via a Helm chart maintained in the comfy-capybara repository (planned)
- **F5 Distributed Cloud (XC)** — cloud-native API security fronting the NIC ingress (planned)

The deployment is orchestrated entirely through GitHub Actions using Terraform with GCS remote state. Local execution is not supported.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ F5 Distributed Cloud (XC)                  (planned block)  │
│ ├─ HTTP Load Balancer                                       │
│ ├─ API Security (WAF + API Discovery + Rate Limit)          │
│ └─ Origin: NIC LoadBalancer Public IP                       │
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
│  │  │ ├─ NGINX Ingress Controller (helm chart 2.0.1) │  │  │
│  │  │ │  └─ NAP sidecars: waf-enforcer + config-mgr  │  │  │
│  │  │ ├─ Policy CRD: waf-policy (compiled bundle)    │  │  │
│  │  │ └─ Service type=LoadBalancer (public IP)       │  │  │
│  │  └────────────────────────────────────────────────┘  │  │
│  │                              │                        │  │
│  │                              ▼  (VirtualServer route) │  │
│  │  ┌────────────────────────────────────────────────┐  │  │
│  │  │ Namespace: comfy-capybara         (planned)    │  │  │
│  │  │ ├─ Deployments: frontend, api, internal-mock,  │  │  │
│  │  │ │              shadow-api, db                  │  │  │
│  │  │ └─ Services (ClusterIP)                        │  │  │
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
4. Workflow: Compile NAP Policy (waf-compiler 5.4.0 Docker image → /tmp/compiled_policy.tgz)
   ↓
5. Terraform: NIC + NAP (Helm release of nginx-ingress chart with NAP V5 sidecars; mounts compiled policy via Secret)
   ↓
6. Terraform: App                   (planned — helm_release of comfy-capybara chart + NIC VirtualServer CRD)
   ↓
7. Terraform: F5 XC                 (planned — origin pool points at NIC LoadBalancer public IP via remote state)
```

**NAP V5 Policy Flow:**
- Policy source lives at `config/uc2/nap/policy.json`
- Workflow runs the `private-registry.nginx.com/nap/waf-compiler:5.4.0` Docker image to produce `/tmp/compiled_policy.tgz`
- Terraform mounts the compiled bundle into a Kubernetes Secret and exposes it to the NIC pods via the chart's `extraVolumes` mechanism
- NIC's `waf-config-mgr` sidecar watches for the bundle and pushes it to the `waf-enforcer` sidecar
- The `Policy` CRD (`waf-policy`) in the `nginx-ingress` namespace is what application `VirtualServer` resources reference for enforcement

**CRD Sourcing:**
- NIC CRDs are pulled from upstream at apply time via `data.http` + `kubectl_file_documents`, pinned by the `nic_crds_url` variable
- No CRDs are vendored into this repo

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
   - CPUs: 8+ (default GKE node pool = 2x `e2-standard-4` = 8 vCPU)
   - External IP addresses: 2+ (NAT gateway + NIC LoadBalancer)
   - Persistent disk: 100+ GB

### F5 NGINX Plus + NAP V5 Requirements

The NIC + NAP V5 images come from `private-registry.nginx.com`, which requires a valid NGINX Plus subscription. You will need:

1. **NGINX JWT Token** — from `MyF5` portal, used for chart/image entitlement
2. **NGINX Repository Client Certificate** — `client.cert` from your NGINX subscription
3. **NGINX Repository Client Key** — `client.key` matched to the certificate

### F5 Distributed Cloud (XC) Requirements (Planned Block)

When the XC block is wired in:

1. **XC Tenant** with API access enabled
2. **API Certificate** (.p12 file) with password
3. **Namespace** — auto-created by Terraform
4. **Custom Domain** configured (optional, or use XC-provided domain)

### GitHub Repository Requirements

1. **Forked Repository** with Actions enabled
2. **Protected Branches:**
   - `deploy-adsp-uc2` — triggers validation + deployment
   - `test-adsp-uc2` — triggers validation only
   - `destroy-adsp-uc2` — triggers destroy workflow
3. **GitHub Secrets** (see Configuration section)

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
│       ├── gcp/env.json             # Use-case 2 GCP + GKE + NIC config
│       └── nap/policy.json          # NAP policy source (compiled in workflow)
├── infra/gcp/                       # Network infrastructure
│   ├── main.tf
│   ├── vpc.tf
│   ├── firewall.tf
│   ├── variables.tf
│   └── outputs.tf
├── k8s/gcp/                         # GKE Standard cluster
│   ├── gke.tf
│   ├── locals.tf
│   ├── variables.tf
│   └── outputs.tf
├── f5/
│   ├── nic/gcp/                     # NIC + NAP V5
│   │   ├── crds.tf
│   │   ├── data.tf
│   │   ├── helm.tf
│   │   ├── locals.tf
│   │   ├── main.tf
│   │   ├── namespace.tf
│   │   ├── outputs.tf
│   │   ├── secrets.tf
│   │   ├── values.yaml.tftpl
│   │   ├── variables.tf
│   │   └── versions.tf
│   └── xc/                          # F5 Distributed Cloud (shared module; UC2 wiring planned)
└── docs/
    ├── ADSP-UC1-GCP.md
    └── ADSP-UC2-GCP.md              # This document
```

### Terraform State Layout

Remote state is stored in GCS bucket `${project_prefix}-state-bucket`:

- `state/uc2/infra/` — VPC, subnets, firewall rules
- `state/uc2/k8s/` — GKE cluster + node pool
- `state/uc2/nic/` — NIC + NAP Helm release, Secrets, CRDs
- `state/uc2/app/` — Application workload (planned)
- `state/uc2/xc/` — F5 Distributed Cloud resources (planned)

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
  "admin_src_addr": ["YOUR.PUBLIC.IP.ADDRESS/32"],
  "tf_state_bucket": ""
}
```

**Required Changes:**
- `gcp_project_id` — GCP project ID
- `gcp_region` — target GCP region
- `gcp_zone` — target GCP zone (must be inside `gcp_region`; GKE cluster is zonal)
- `project_prefix` — unique prefix for resource naming (lowercase, alphanumeric)
- `resource_owner` — initials or identifier used for resource labels
- `admin_src_addr` — public IP CIDRs allowed to reach management interfaces and the GKE control plane (array of CIDRs)

**Leave as-is:**
- `tf_state_bucket` — auto-generated as `${project_prefix}-state-bucket`

### Step 2: Configure Use-Case Settings

Copy `config/uc2/gcp/env.example.json` to `config/uc2/gcp/env.json` and edit:

```json
{
  "features": {
    "gke": true,
    "nic": true
  },
  "k8s": {
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

**Customizable Settings (`k8s` block):**
- `release_channel` — `RAPID`, `REGULAR`, or `STABLE`
- `node_machine_type` — GKE node machine type
- `node_count` — number of nodes in the pool
- `node_disk_size_gb` / `node_disk_type` — node boot disk
- `master_ipv4_cidr_block` — control-plane private endpoint CIDR (must not overlap with subnets)
- `master_authorized_networks_extra` — additional CIDRs allowed to reach the GKE control plane on top of `admin_src_addr`

**Customizable Settings (`nic` block):**
- `chart_version` / `nic_image_tag` — pin specific NIC versions
- `nap_enforcer_tag` / `nap_config_mgr_tag` — pin NAP V5 sidecar versions (must match `waf-compiler` tag used in workflow)
- `nic_crds_url` — pin CRD source to a specific NIC release (must match `nic_image_tag`)
- `waf_policy_name` — name of the `Policy` CRD that apps reference from their `VirtualServer`

**Do Not Modify:**
- `features.gke: true` / `features.nic: true` — required for UC2

### Step 3: Configure NAP Policy

Edit `config/uc2/nap/policy.json` to declare the policy. The default is a baseline blocking policy on the NGINX base template:

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

The workflow compiles this with `waf-compiler:5.4.0` before invoking the NIC Terraform module. Any NAP policy JSON the compiler accepts is valid here.

### Step 4: Configure F5 XC Settings (Planned)

Once the XC block ships, the `config/uc2/xc/env.json` shape will mirror `config/uc1/xc/env.json` with these UC2-specific differences:
- `backend_bigip: false` — no BIG-IP in this UC
- `origin_server` — auto-resolved from NIC remote state output (`nic_external_ip`)
- `xc_app_type`, API discovery / rate limit / etc. toggled via `xc_features` as needed

---

## GitHub Secrets Setup

Configure the following secrets in GitHub repository settings: `Settings → Secrets and variables → Actions → New repository secret`

### Required Secrets

| Secret Name | Description | How to Obtain |
|-------------|-------------|---------------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Workload Identity Provider resource name | Format: `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_ID/providers/PROVIDER_ID` |
| `GCP_SERVICE_ACCOUNT` | Service account email for GCP authentication | Format: `SERVICE_ACCOUNT_NAME@PROJECT_ID.iam.gserviceaccount.com` |
| `NGINX_JWT` | NGINX Plus entitlement JWT | Download from `MyF5` portal under your NGINX Plus subscription |
| `NGINX_REPO_CRT` | Client certificate for `private-registry.nginx.com` | `nginx-repo.crt` from NGINX subscription bundle |
| `NGINX_REPO_KEY` | Client key for `private-registry.nginx.com` | `nginx-repo.key` from NGINX subscription bundle |

### Required Secrets (Planned XC Block)

| Secret Name | Description | How to Obtain |
|-------------|-------------|---------------|
| `VES_P12_CONTENT` | Base64-encoded XC API certificate (.p12 file) | Run: `base64 -w 0 /path/to/certificate.p12` (Linux) or `base64 -i /path/to/certificate.p12` (macOS) |
| `VES_P12_PASSWORD` | Password for XC API certificate | Provided when downloading certificate from XC console |

### Workload Identity Federation Setup

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

## Deployment Procedures

### Initial Deployment

1. **Fork this repository** to your GitHub organization or account
2. **Configure files:**
   - `config/common/gcp/env.json`
   - `config/uc2/gcp/env.json`
   - `config/uc2/nap/policy.json`
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
1. F5 XC resources (when XC block is wired)
2. Application workload (when app block is wired)
3. NIC + NAP Helm release
4. GKE cluster
5. Network infrastructure
6. GCS state bucket (including all history)

---

## Accessing Deployment Outputs

### Via Terraform Cloud Shell

Activate Cloud Shell in GCP Console, then:

```bash
PROJECT_PREFIX="your-prefix"
STATE_BUCKET="${PROJECT_PREFIX}-state-bucket"

# Get GKE cluster name
gsutil cat gs://${STATE_BUCKET}/state/uc2/k8s/default.tfstate | \
  jq -r '.outputs.cluster_name.value'

# Get NIC LoadBalancer public IP (XC origin)
gsutil cat gs://${STATE_BUCKET}/state/uc2/nic/default.tfstate | \
  jq -r '.outputs.nic_external_ip.value'

# Get NIC namespace
gsutil cat gs://${STATE_BUCKET}/state/uc2/nic/default.tfstate | \
  jq -r '.outputs.nic_namespace.value'

# Get WAF Policy name + namespace (referenced by VirtualServer)
gsutil cat gs://${STATE_BUCKET}/state/uc2/nic/default.tfstate | \
  jq -r '.outputs.waf_policy_name.value, .outputs.waf_policy_namespace.value'
```

### Connect kubectl to the GKE Cluster

```bash
PROJECT_ID="your-gcp-project-id"
REGION="your-gcp-region"
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
| `nic_namespace` | nic | Namespace hosting the NIC release and WAF Policy CRD |
| `nic_service_name` | nic | Kubernetes Service name for the NIC LoadBalancer |
| `nic_external_ip` | nic | External IP assigned to the NIC LoadBalancer (XC origin) |
| `waf_policy_name` | nic | Name of the NIC Policy resource exposing the NAP bundle |
| `waf_policy_namespace` | nic | Namespace of the WAF Policy resource (apps cross-reference it) |

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

# Inspect NIC logs for ingress events
kubectl -n "${NIC_NS}" logs -l app.kubernetes.io/name=nginx-ingress -c nginx-ingress --tail=100

# Inspect NAP sidecars
kubectl -n "${NIC_NS}" logs -l app.kubernetes.io/name=nginx-ingress -c waf-config-mgr --tail=100
kubectl -n "${NIC_NS}" logs -l app.kubernetes.io/name=nginx-ingress -c waf-enforcer  --tail=100
```

### NIC LoadBalancer Reachability

```bash
NIC_IP=$(gsutil cat gs://${STATE_BUCKET}/state/uc2/nic/default.tfstate | \
  jq -r '.outputs.nic_external_ip.value')

curl -kI "https://${NIC_IP}/"
```

Until the app block is wired you should expect a 404 from NIC; the LoadBalancer IP is what matters.

### Application Reachability (Once App Block Ships)

```bash
# Direct through NIC LoadBalancer
curl -H "Host: your-app.example.com" "http://${NIC_IP}/"

# Through XC (once XC block ships)
curl "https://your-app.example.com"
```

### NAP Policy Enforcement Smoke Test

Once an app `VirtualServer` references the `waf-policy`, a baseline SQLi-style probe should be blocked at NIC:

```bash
curl -i -H "Host: your-app.example.com" "http://${NIC_IP}/?id=1%20OR%201=1"
# Expect 4xx with NAP support id header
```

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

### GKE Control Plane Unreachable

**Error:** `Error: Get "https://...": dial tcp ...:443: i/o timeout` during NIC apply

**Resolution:**
- GKE control plane is private; the runner reaches it via authorized networks
- Confirm `admin_src_addr` in `config/common/gcp/env.json` includes the runner's egress IPs, or use `master_authorized_networks_extra` to add GitHub Actions hosted runner egress ranges
- The cluster endpoint is public-but-restricted: verify the firewall rule and the cluster's `master_authorized_networks_config`

### NIC Pods CrashLoopBackOff (Image Pull)

**Error:** `ErrImagePull` or `ImagePullBackOff` on NIC or NAP sidecar containers

**Resolution:**
- The `NGINX_REPO_CRT` / `NGINX_REPO_KEY` secrets must match the certificate associated with your active NGINX Plus subscription
- Verify the docker certs install step succeeded in the workflow log
- Sanity-check the secret content has no truncation or extra whitespace
- Confirm the `nic_image_tag` and NAP sidecar tags exist at `private-registry.nginx.com`

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
- The compiler version (`5.4.0`) must match the `nap_enforcer_tag` and `nap_config_mgr_tag` in `config/uc2/gcp/env.json`

### NIC LoadBalancer Pending External IP

**Error:** `kubectl get svc -n nginx-ingress` shows `EXTERNAL-IP: <pending>` for minutes

**Resolution:**
- GKE provisions the LoadBalancer via a target pool; confirm the node pool is healthy: `kubectl get nodes`
- Check GCP regional quota for forwarding rules
- Inspect Service events: `kubectl -n nginx-ingress describe svc`

### XC Provider Errors (Planned Block)

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

### Terraform Variable Errors

**Error:** `No value for required variable`

**Resolution:**
- Verify all required fields are set in `env.json` files
- Check workflow logs for variable generation step
- Validate JSON syntax: `jq . config/uc2/gcp/env.json`

### Quota Exceeded Errors

**Error:** `Quota 'CPUS' exceeded. Limit: X in region Y`

**Resolution:**
- Request quota increase in GCP Console: `IAM & Admin → Quotas`
- Reduce `node_machine_type` or `node_count` in `config/uc2/gcp/env.json`

---

## Operations

Restrict `admin_src_addr` in `config/common/gcp/env.json` to known IP ranges and apply branch protection to `deploy-adsp-uc2` and `destroy-adsp-uc2` before using this in any environment that matters. The GKE control plane is reachable only from the union of `admin_src_addr` and `master_authorized_networks_extra` — keep that surface as small as it can be.

State files should not be edited by hand. Back up state before major changes:

```bash
gsutil -m cp -r gs://${STATE_BUCKET}/state/uc2 gs://backup-bucket/state-uc2-$(date +%Y%m%d)
```

Destroy environments when idle. The GKE Standard cluster's node pool is the dominant ongoing cost — see [Cost Estimates](#cost-estimates).

---

## Cost Estimates

Estimated monthly costs for `us-west1` region (as of 2026, defaults from `config/uc2/gcp/env.example.json`):

| Component | Instance Type | Hours/Month | Est. Cost/Month |
|-----------|---------------|-------------|-----------------|
| GKE Standard cluster management | — | 730 | ~$73 (one cluster fee waiver applies per billing account) |
| Node pool (2× e2-standard-4) | e2-standard-4 | 730 | ~$200 |
| Node boot disks (2× 50 GB pd-balanced) | pd-balanced | 730 | ~$10 |
| Cloud NAT | — | 730 | ~$33 |
| External IPs (NAT + NIC LB) | Standard | 730 | ~$15 |
| Network Egress | Variable | — | ~$10 |
| **Total (GCP)** | | | **~$340/month** |
| F5 NGINX Plus + NAP V5 | — | — | Contact F5 Sales |
| F5 Distributed Cloud | — | — | Contact F5 Sales |

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

---

**Last Updated:** 2026-05-28
**Terraform Version:** >= 1.3.0
**Target GCP Regions:** All (tested on us-west1)
