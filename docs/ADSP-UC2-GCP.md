# Deploy UC2 in Google Cloud

NGINX Ingress Controller with NAP V5 on GKE, fronted by F5 Distributed Cloud HTTP LoadBalancer with WAF and API protection. Deployment is driven entirely by GitHub Actions; local execution is not supported.

This document has two parts:

- **Part 1 - Quickstart**: the minimum set of edits to get UC2 running, assuming you already have GCP + WIF + F5 entitlements wired up.
- **Part 2 - Detailed Reference**: architecture, IAM model, full configuration surface, verification, and troubleshooting.

---

# Part 1: Quickstart

## What gets built

```
F5 Distributed Cloud HTTPS LoadBalancer (public domain, auto-cert)
  - WAF (blocking)
  - API Protection: validation in report mode, fall-through in report mode
            |
            v
GKE Standard cluster (private nodes, public control plane locked to admin CIDRs)
  - NIC + NAP V5 sidecars     (namespace: nginx-ingress)
  - comfy-capybara workload   (namespace: comfy-capybara)
```

UC2 ships with all per-feature toggles already set in the example env files. You only edit the per-environment values listed below.

## Edits required

Copy the four `env.example.json` files to `env.json` and edit only the fields listed.

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

Edit only if you need to change the GKE shape or master CIDR. Everything else is set correctly for UC2.

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

## Deploy

```bash
git checkout -b deploy-adsp-uc2 && git push -u origin deploy-adsp-uc2
```

Watch the workflow in the Actions tab. Modules run sequentially: state bucket → infra → GKE → NIC+NAP → app → XC.

`test-adsp-uc2` runs validate only. `destroy-adsp-uc2` tears down in reverse order.

---

# Part 2: Detailed Reference

## Architecture

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

## Deployment flow

```
1. Bootstrap state bucket (GCS)
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

NAP policy lives at `config/uc2/nap/policy.json`. The workflow runs the `private-registry.nginx.com/nap/waf-compiler:5.4.0` image to produce `/tmp/compiled_policy.tgz`, then Terraform mounts the compiled bundle into a Kubernetes Secret. The NIC `waf-config-mgr` sidecar watches the Secret and pushes it to `waf-enforcer`. Applications reference enforcement via the `Policy` CRD (`waf-policy`) in the `nginx-ingress` namespace.

NIC CRDs are pulled from upstream at apply time via `data.http` + `kubectl_file_documents`, pinned by the `nic_crds_url` variable. No CRDs are vendored.

The OpenAPI spec at `config/uc2/app/oas/openapi.json` is base64-encoded by the workflow and passed to the XC module as `xc_oas_content`. The XC `volterra_api_definition` resource references it inline (`string:///<base64>`). The `volterra_http_loadbalancer` attaches the api_definition with validation active in report mode and fall-through in report mode by default.

Destroy operations run in reverse: `XC → App → NIC → GKE → Infra → State Bucket`.

## Prerequisites

### GCP

1. GCP project with billing enabled.
2. APIs enabled: Compute Engine, Kubernetes Engine, Cloud Resource Manager, Cloud Storage, IAM Service Account Credentials.
3. Pre-create the Terraform state bucket. UC2's deploy workflow names it `<project_prefix>-state-bucket` and expects it to already exist with versioning and public-access-prevention enabled (this lets the deploy SA stay narrow on storage):
   ```bash
   gcloud storage buckets create gs://<project_prefix>-state-bucket \
     --project=<project-id> \
     --location=<region> \
     --uniform-bucket-level-access
   gcloud storage buckets update gs://<project_prefix>-state-bucket \
     --versioning --public-access-prevention
   ```
4. Two service accounts:
   - **Deploy SA** - assumed by GitHub Actions via Workload Identity Federation.
   - **Runtime SA** - attached to GKE nodes.

#### Deploy SA roles

| Role | Scope | Why |
|------|-------|-----|
| `roles/compute.networkAdmin` | project | VPC, subnets, router, NAT (infra module). |
| `roles/compute.securityAdmin` | project | Firewall rules (infra module). |
| `roles/container.clusterAdmin` | project | GKE cluster + node pool CRUD (k8s module). |
| `roles/container.developer` | project | Push manifests / helm into the cluster (NIC, app modules). |
| `roles/storage.admin` | **bucket** (`<project_prefix>-state-bucket`) | Read/write state objects and AS3 / OAS / compiled-policy artifacts under that bucket. Bind on the bucket only, not project-wide. |
| `roles/iam.serviceAccountUser` | **runtime SA only** | Lets the deploy SA attach the runtime SA to GKE nodes. Do not grant this project-wide. |
| `roles/iam.workloadIdentityUser` | deploy SA itself (via principalSet) | WIF binding so the GitHub OIDC token can assume the deploy SA. |

#### Runtime SA roles (attached to GKE nodes)

| Role | Scope | Why |
|------|-------|-----|
| `roles/logging.logWriter` | project | Node + workload logs to Cloud Logging. |
| `roles/monitoring.metricWriter` | project | Node + workload metrics to Cloud Monitoring. |
| `roles/monitoring.viewer` | project | Required by the metrics agent on nodes. |
| `roles/stackdriver.resourceMetadata.writer` | project | Cloud Ops resource metadata. |

#### Binding commands

```bash
PROJECT=<project-id>
PREFIX=<project_prefix>
BUCKET=$PREFIX-state-bucket
DEPLOY_SA=<deploy-sa>@$PROJECT.iam.gserviceaccount.com
RUNTIME_SA=<runtime-sa>@$PROJECT.iam.gserviceaccount.com

# Deploy SA - project-scoped
for ROLE in roles/compute.networkAdmin roles/compute.securityAdmin \
            roles/container.clusterAdmin roles/container.developer; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:$DEPLOY_SA" --role="$ROLE"
done

# Deploy SA - bucket-scoped storage admin
gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
  --member="serviceAccount:$DEPLOY_SA" --role="roles/storage.admin"

# Deploy SA - allowed to act-as the runtime SA only
gcloud iam service-accounts add-iam-policy-binding "$RUNTIME_SA" \
  --member="serviceAccount:$DEPLOY_SA" --role="roles/iam.serviceAccountUser"

# Runtime SA - GKE node telemetry
for ROLE in roles/logging.logWriter roles/monitoring.metricWriter \
            roles/monitoring.viewer roles/stackdriver.resourceMetadata.writer; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:$RUNTIME_SA" --role="$ROLE"
done
```

5. Workload Identity Pool + Provider for GitHub Actions (see [GitHub Secrets Setup](#github-secrets-setup)).
6. Regional quotas: 8 vCPU minimum (default GKE node pool is 2× `e2-standard-4`), 2 external IPs (NAT + NIC LoadBalancer), 100 GB persistent disk.

### F5 NGINX Plus + NAP V5

NIC + NAP V5 images come from `private-registry.nginx.com` and require a valid NGINX Plus subscription:

- NGINX JWT token (from MyF5)
- `nginx-repo.crt` and `nginx-repo.key` from the subscription bundle

### F5 Distributed Cloud

- XC tenant with API access enabled.
- API certificate (`.p12`) and password.
- A custom domain you control for `app_domain` (XC also supports tenant-provided domains).

### GitHub repository

- Repository forked with Actions enabled.
- Branches:
  - `deploy-adsp-uc2` - validate + plan + apply
  - `test-adsp-uc2` - validate only
  - `destroy-adsp-uc2` - destroy workflow

## GitHub Secrets Setup

`Settings → Secrets and variables → Actions → New repository secret`:

| Secret | Value |
|--------|-------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/<num>/locations/global/workloadIdentityPools/<pool>/providers/<provider>` |
| `GCP_SERVICE_ACCOUNT` | deploy service account email |
| `NGINX_JWT` | contents of your NGINX Plus `.jwt` |
| `NGINX_REPO_CRT` | contents of `nginx-repo.crt` |
| `NGINX_REPO_KEY` | contents of `nginx-repo.key` |
| `VES_P12_CONTENT` | `base64 -w 0 api.p12` output |
| `VES_P12_PASSWORD` | password for the `.p12` |

All secret values are the file contents (PEM/JWT body / base64 blob), not file paths.

### Workload Identity Federation

```bash
PROJECT=<project-id>
POOL=github-actions-pool
PROVIDER=github-provider
DEPLOY_SA=<deploy-sa>@$PROJECT.iam.gserviceaccount.com
REPO=<github-org>/<repo>

gcloud iam workload-identity-pools create "$POOL" \
  --project="$PROJECT" --location=global \
  --display-name="GitHub Actions Pool"

gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
  --project="$PROJECT" --location=global \
  --workload-identity-pool="$POOL" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"

PROJECT_NUM=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')
gcloud iam service-accounts add-iam-policy-binding "$DEPLOY_SA" \
  --project="$PROJECT" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUM/locations/global/workloadIdentityPools/$POOL/attribute.repository/$REPO"
```

The `GCP_WORKLOAD_IDENTITY_PROVIDER` secret value matches:
`projects/$PROJECT_NUM/locations/global/workloadIdentityPools/$POOL/providers/$PROVIDER`

## Repository structure

```
F5-ADSP-Automation/
├── .github/workflows/
│   ├── deploy-adsp-uc2-gcp.yml       # Main deployment workflow
│   ├── destroy-adsp-uc2-gcp.yml      # Destroy workflow
│   └── pr_tf_validate.yml            # PR validation
├── config/
│   ├── common/gcp/env.json           # Shared GCP settings
│   └── uc2/
│       ├── gcp/env.json              # UC2 GCP + GKE + NIC config
│       ├── nap/policy.json           # NAP policy source (compiled in workflow)
│       ├── app/
│       │   ├── env.json              # comfy-capybara chart + VirtualServer config
│       │   └── oas/openapi.json      # OpenAPI spec for the app (you drop this)
│       └── xc/env.json               # XC tenant + LoadBalancer + WAF/API feature flags
├── infra/gcp/                        # VPC, subnets, firewall, NAT
├── k8s/gcp/                          # GKE Standard cluster
├── f5/
│   ├── nic/gcp/                      # NIC + NAP V5 helm release
│   └── xc/                           # F5 Distributed Cloud (shared module)
├── app/gcp/                          # comfy-capybara helm_release + VirtualServer
└── docs/ADSP-UC2-GCP.md              # This document
```

### Terraform state layout

Remote state lives in `gs://<project_prefix>-state-bucket/`:

- `state/uc2/infra/` - VPC, subnets, firewall rules
- `state/uc2/k8s/` - GKE cluster + node pool
- `state/uc2/nic/` - NIC + NAP helm release, Secrets, CRDs
- `state/uc2/app/` - comfy-capybara helm release, namespace
- `state/uc2/xc/` - XC namespace, HTTP LB, WAF policy, api_definition

## Configuration

Five files drive UC2. Copy each `env.example.json` to `env.json` and edit only what's called out; the rest of the example values are correct for UC2 and should not be changed unless you're tuning specific behavior.

### Common (`config/common/gcp/env.json`)

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

- `admin_src_addr`: JSON array of quoted CIDR strings (`IP/prefix`). Each entry must include the prefix (`/32` for a single host). Bare IPs and unquoted values fail JSON parsing in the infra job.
- `tf_state_bucket`: leave empty. The workflow derives it as `<project_prefix>-state-bucket`.

### UC2 GCP + GKE + NIC (`config/uc2/gcp/env.json`)

The example file pre-enables `features.gke` and `features.nic` and sets:

- GKE: `REGULAR` release channel, 2× `e2-standard-4` nodes, 50 GB pd-balanced disks, master CIDR `172.16.0.0/28`.
- NIC: chart 2.0.1, image tag 4.0.1, NAP V5 sidecars at 5.4.0, CRD source pinned to NIC v4.0.1.

Customize only if you need a different GKE shape or need to pin NIC/NAP to a different version (compiler version must match NAP sidecar versions).

### App (`config/uc2/app/env.json`)

```json
{
  "app": {
    "app_host": "<fqdn>"
  }
}
```

The chart is published at `oci://ghcr.io/knowbase/charts/comfy-capybara`. The `app/gcp` Terraform module is a `helm_release` shim with `values` overrides, plus a `kubectl_manifest` resource that emits the NIC `VirtualServer` pointing at the chart's frontend and api Services.

Fields that stay at the example default:

- `chart_version` (`0.1.0`)
- `attach_waf_server_wide: true` + `attach_waf_to_api_route: true` - both attach `waf-policy` (cross-namespace from `nginx-ingress`) for defense in depth
- `vs_tls_enabled: false` - TLS terminates at XC, not at NIC

### OpenAPI spec (`config/uc2/app/oas/openapi.json`)

Drop the OpenAPI spec for the app at this path. `.yaml` and `.yml` are also accepted. The workflow base64-encodes it and feeds it into the XC `volterra_api_definition` resource inline (`swagger_specs = ["string:///<base64>"]`). The XC job fails clearly if the file is missing.

### NAP policy (`config/uc2/nap/policy.json`)

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

### XC (`config/uc2/xc/env.json`)

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

Fields that stay at the example default for UC2:

- `backend_nic: true`, `origin_server: ""` - origin pool resolves the NIC LoadBalancer IP from `state/uc2/nic`.
- `xc_waf_blocking: true`
- `xc_api_pro: true`, `xc_api_val: true`, `xc_api_val_all: true`, `xc_api_val_active: true` - API protection on with active validation.
- `enforcement_report: true`, `enforcement_block: false` - validation events are reports, not blocks.
- `fall_through_mode_allow: false`, `fall_through_mode_report: true` - unknown paths are reported, not blocked.
- `xc_api_disc: false`, `xc_api_crawler: false`, `xc_api_auth_discovery: false` - discovery / crawler / auth discovery off.

The full set of available feature flags is in [f5/xc/variables.tf](../f5/xc/variables.tf).

## Deployment Procedures

### Initial deploy

1. Fork the repo.
2. Edit the five config files in `config/`.
3. Set GitHub Secrets.
4. Push your edits to your default branch.
5. Cut and push the deploy branch:
   ```bash
   git checkout -b deploy-adsp-uc2 && git push -u origin deploy-adsp-uc2
   ```
6. Watch the workflow in the Actions tab.

### Validation only

```bash
git checkout -b test-adsp-uc2 && git push -u origin test-adsp-uc2
```

Runs `terraform validate` for every module; skips plan and apply.

### Update an existing deployment

1. Edit config on the default branch.
2. Merge or push to `deploy-adsp-uc2`. The workflow re-runs plan + apply.

### Destroy

```bash
git checkout -b destroy-adsp-uc2 && git push -u origin destroy-adsp-uc2
```

Destroy order: XC → App → NIC → GKE → Infra. The state bucket is not deleted by the workflow since it was created out of band; remove it manually with `gcloud storage rm --recursive gs://<bucket>` when you're done with the demo.

## Accessing deployment outputs

```bash
BUCKET="<project_prefix>-state-bucket"

gsutil cat gs://$BUCKET/state/uc2/k8s/default.tfstate \
  | jq -r '.outputs.cluster_name.value'

gsutil cat gs://$BUCKET/state/uc2/nic/default.tfstate \
  | jq -r '.outputs.nic_external_ip.value, .outputs.nic_namespace.value, .outputs.waf_policy_name.value'

gsutil cat gs://$BUCKET/state/uc2/app/default.tfstate \
  | jq -r '.outputs.app_host.value, .outputs.app_namespace.value, .outputs.virtualserver_name.value'

gsutil cat gs://$BUCKET/state/uc2/xc/default.tfstate \
  | jq -r '.outputs.endpoint.value, .outputs.xc_lb_name.value, .outputs.xc_waf_name.value'
```

### kubectl against the cluster

```bash
PROJECT=<project-id>
ZONE=<zone>
CLUSTER=$(gsutil cat gs://$BUCKET/state/uc2/k8s/default.tfstate \
  | jq -r '.outputs.cluster_name.value')
gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT"
```

### Key outputs reference

| Output | Module | Description |
|--------|--------|-------------|
| `cluster_name` | k8s | GKE cluster name |
| `cluster_endpoint` | k8s | Control plane endpoint |
| `nic_namespace` | nic | Namespace hosting NIC and the WAF Policy CRD |
| `nic_external_ip` | nic | NIC LoadBalancer public IP (XC origin) |
| `waf_policy_name` | nic | Policy CRD name apps reference |
| `app_host` | app | FQDN exposed by the NIC VirtualServer |
| `virtualserver_name` | app | VirtualServer CRD emitted by the chart |
| `endpoint` | xc | XC public domain |
| `xc_lb_name` | xc | XC HTTP LB resource name |
| `xc_waf_name` | xc | XC WAF policy resource name |

## Verification and Testing

### Cluster + NIC

```bash
kubectl get nodes
kubectl get ns

NIC_NS=$(gsutil cat gs://$BUCKET/state/uc2/nic/default.tfstate | jq -r '.outputs.nic_namespace.value')
kubectl -n "$NIC_NS" get pods -o wide
kubectl -n "$NIC_NS" get svc
kubectl -n "$NIC_NS" get policies
```

Each NIC pod runs three containers: `nginx-ingress`, `waf-enforcer`, `waf-config-mgr`. Logs:

```bash
kubectl -n "$NIC_NS" logs -l app.kubernetes.io/name=nginx-ingress -c nginx-ingress --tail=100
kubectl -n "$NIC_NS" logs -l app.kubernetes.io/name=nginx-ingress -c waf-config-mgr --tail=100
kubectl -n "$NIC_NS" logs -l app.kubernetes.io/name=nginx-ingress -c waf-enforcer  --tail=100
```

### Application

```bash
APP_NS=$(gsutil cat gs://$BUCKET/state/uc2/app/default.tfstate | jq -r '.outputs.app_namespace.value')
kubectl -n "$APP_NS" get pods
kubectl -n "$APP_NS" get virtualservers
kubectl -n "$APP_NS" describe virtualserver
```

### Reachability

```bash
NIC_IP=$(gsutil cat gs://$BUCKET/state/uc2/nic/default.tfstate | jq -r '.outputs.nic_external_ip.value')
APP_HOST=$(gsutil cat gs://$BUCKET/state/uc2/app/default.tfstate | jq -r '.outputs.app_host.value')

# Direct to NIC (Host header drives VirtualServer match)
curl -H "Host: $APP_HOST" "http://$NIC_IP/"
curl -H "Host: $APP_HOST" "http://$NIC_IP/api/healthz"

# Through XC
curl "https://$APP_HOST/"
curl "https://$APP_HOST/api/healthz"
```

Without a matching `Host` header NIC returns 404; that's expected.

### WAF smoke tests

NAP at NIC blocks the request when `attach_waf_server_wide=true` (default):

```bash
curl -i -H "Host: $APP_HOST" "http://$NIC_IP/api/users?id=1%20OR%201=1"
kubectl -n "$NIC_NS" logs -l app.kubernetes.io/name=nginx-ingress -c waf-enforcer --tail=50 -f
```

XC WAF blocks the same probe at the edge in blocking mode:

```bash
curl -i "https://$APP_HOST/api/users?id=1%20OR%201=1"
```

### API protection

In the XC console, open `Multi-Cloud App Connect → HTTP Load Balancers → <your LB> → Security Events`. Validation events appear for any request that fails OAS conformance; fall-through events appear for requests against paths not declared in the OAS. With the defaults UC2 ships (validation report, fall-through report) nothing is blocked at this layer; switch `enforcement_block: true` and `fall_through_mode_report: false` if you want enforcement.

## Troubleshooting

**`jq: parse error: Invalid numeric literal` in the infra job.**
Your `admin_src_addr` (or another CIDR/list field) has unquoted values. JSON requires `["1.2.3.4/32"]`, not `[1.2.3.4/32]`.

**XC job fails with `No OAS spec found at config/uc2/app/oas/...`.**
Drop your OpenAPI spec at `config/uc2/app/oas/openapi.json` (or `.yaml` / `.yml`) and re-run.

**Bootstrap job fails with `Required "storage.buckets.create" permission` or similar storage error.**
The deploy SA's storage role is bucket-scoped, so the bucket must exist before the workflow runs. Pre-create it with the gcloud commands in [Prerequisites → GCP](#gcp).

**GKE control plane unreachable during NIC apply (`dial tcp ...:443: i/o timeout`).**
GKE control plane is private; the runner reaches it via authorized networks. Confirm `admin_src_addr` in `config/common/gcp/env.json` includes the runner's egress IPs, or use `master_authorized_networks_extra` in `config/uc2/gcp/env.json` to add GitHub Actions hosted-runner egress ranges.

**NIC pods `ImagePullBackOff`.**
The `NGINX_REPO_CRT` / `NGINX_REPO_KEY` secrets either don't match your active NGINX Plus subscription or got truncated when pasted. Sanity-check the workflow's "Install docker certs" step succeeded and the secret content has no trailing whitespace. Also confirm `nic_image_tag` and the NAP sidecar tags exist at `private-registry.nginx.com`.

**NAP compiler step fails.**
The compiler image needs the same docker certs install that NIC images use. Confirm the install step succeeded. The compiler version (`5.4.0` by default) must match `nap_enforcer_tag` and `nap_config_mgr_tag` in `config/uc2/gcp/env.json`.

**App pods `ImagePullBackOff`.**
Default images come from `ghcr.io/knowbase/comfy-capybara-*`. If you forked the comfy-capybara repo, set `image_registry` in `config/uc2/app/env.json` to your fork's GHCR namespace. Private images need `image_pull_secret_name` to point at a pre-created `Secret` in the app namespace.

**`VirtualServer` shows `Policy not found` or NAP isn't enforcing.**
The chart's VirtualServer references `waf-policy` cross-namespace in `nginx-ingress`. Confirm `kubectl -n nginx-ingress get policies` shows the policy. If both `attach_waf_server_wide` and `attach_waf_to_api_route` are false, the VirtualServer ships without policy refs; flip at least one to `true`.

**NIC LoadBalancer stuck `<pending>` external IP.**
GKE provisions the LB via target pools; check `kubectl -n nginx-ingress describe svc` and regional forwarding-rule quota.

**XC origin shows down / `https://<app_domain>` returns 502.**
- Confirm `backend_nic: true` in `config/uc2/xc/env.json`.
- Confirm the NIC LoadBalancer has an external IP (see above).
- `app_domain` in the XC config must equal `app.app_host` in the app config. If they drift, XC forwards a Host header NIC's VirtualServer won't match and the origin looks healthy while the app is unreachable.
- Direct-to-NIC reachability must work before XC will look healthy.

**XC API definition apply fails.**
Confirm the OAS file under `config/uc2/app/oas/` parses as valid OpenAPI 3.x. The XC API expects an OpenAPI document, not a Postman collection or raw Swagger 1.x.

**`VES_P12_CONTENT` / `VES_P12_PASSWORD` errors.**
Verify `VES_P12_CONTENT` decodes back to a valid `.p12` (`echo "$VES_P12_CONTENT" | base64 -d > /tmp/test.p12 && openssl pkcs12 -info -in /tmp/test.p12 -nokeys`). Re-download from the XC console if the cert is expired.

## Operations

- Restrict `admin_src_addr` to known IP ranges and protect the `deploy-adsp-uc2` / `destroy-adsp-uc2` branches with branch protection rules. The GKE control plane is reachable only from the union of `admin_src_addr` and `master_authorized_networks_extra`; keep that surface small.
- State files should not be edited by hand. Back up state before major changes:
  ```bash
  gsutil -m cp -r gs://$BUCKET/state/uc2 gs://backup-bucket/state-uc2-$(date +%Y%m%d)
  ```
- Destroy environments when idle. The GKE Standard cluster's node pool is the dominant ongoing cost.

## Cost estimates (us-west1, defaults)

| Component | Hours/Month | Est. Cost/Month |
|-----------|-------------|-----------------|
| GKE Standard cluster management | 730 | ~$73 (one free cluster per billing account) |
| Node pool (2× e2-standard-4) | 730 | ~$200 |
| Node boot disks (2× 50 GB pd-balanced) | 730 | ~$10 |
| Cloud NAT | 730 | ~$33 |
| External IPs (NAT + NIC LB) | 730 | ~$15 |
| Network egress | variable | ~$10 |
| **Total (GCP)** | | **~$340/mo** |
| F5 NGINX Plus + NAP V5 | - | per subscription |
| F5 Distributed Cloud | - | per subscription |

Reduce cost by destroying when idle, dropping to a single node, shrinking disks to 30 GB, or moving to `e2-standard-2` if the workload fits.
