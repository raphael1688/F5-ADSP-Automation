# Deploy UC1 in Google Cloud

F5 BIG-IP with AWAF fronting vulnerable applications (Juice Shop and / or crAPI), with F5 Distributed Cloud HTTP LoadBalancer + WAF on top. Deployment is driven entirely by GitHub Actions; local execution is not supported.

This document has two parts:

- **Part 1 - Quickstart**: the minimum set of edits to get UC1 running, assuming you already have GCP + WIF + F5 entitlements wired up.
- **Part 2 - Detailed Reference**: architecture, IAM model, full configuration surface, verification, and troubleshooting.

---

# Part 1: Quickstart

## What gets built

```
F5 Distributed Cloud HTTPS LoadBalancer (public domain, auto-cert)
  - WAF (blocking by default)
  - Origin: BIG-IP public IP (resolved from BIG-IP remote state)
            |
            v
F5 BIG-IP (single-NIC, PAYG, n2-highmem-4)
  - AWAF: AS3 declaration polled from GCS on boot
  - Pool members: Juice Shop and/or crAPI VMs
            |
            v
Docker VMs running the vulnerable apps (e2-micro)
```

UC1 ships with the feature flags pre-set in the example env files. You edit only the per-environment fields below.

## Edits required

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

### `config/uc1/gcp/env.json`

```json
{
  "compute": {
    "gcp_runtime_service_account_email": "<runtime-sa>@<project-id>.iam.gserviceaccount.com"
  }
}
```

The runtime SA email is the one attached to BIG-IP and to the vulnerable-app VMs. Every other field keeps its example default.

### `config/uc1/xc/env.json`

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

`xc_namespace` cannot be `system` or `shared`. `backend_bigip: true` is already set; XC resolves the origin from BIG-IP remote state.

## Deploy

```bash
git checkout -b deploy-adsp-uc1 && git push -u origin deploy-adsp-uc1
```

Watch the workflow in the Actions tab. Modules run: state bucket → infra → compute → bigip-config → bigip-base → XC.

`test-adsp-uc1` runs validate only. `destroy-adsp-uc1` tears down in reverse order.

---

# Part 2: Detailed Reference

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ F5 Distributed Cloud (XC)                                   │
│ ├─ HTTPS LoadBalancer (auto-cert)                           │
│ ├─ WAF Policy                                               │
│ └─ Origin: BIG-IP Public IP (from bigip-base remote state)  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ GCP VPC (${project_prefix}-vpc-*)                           │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ F5 BIG-IP (Single-NIC, PAYG)                         │  │
│  │ ├─ Management GUI/SSH (Public IP)                    │  │
│  │ ├─ AS3 polled from gs://.../artifacts/uc1/as3/       │  │
│  │ └─ Pool members: Juice Shop, crAPI                   │  │
│  └──────────────────────────────────────────────────────┘  │
│                              │                              │
│                              ▼                              │
│  ┌────────────────────┐  ┌────────────────────┐           │
│  │ Juice Shop VM      │  │ crAPI VM           │           │
│  │ (Docker)           │  │ (Docker)           │           │
│  └────────────────────┘  └────────────────────┘           │
│                                                             │
│  Subnets: mgmt (/24), ext (/18), int (/18), app (/18)     │
└─────────────────────────────────────────────────────────────┘
```

## Deployment flow

```
1. Bootstrap state bucket (GCS) - bucket pre-created out of band
   ↓
2. Terraform: Infra (VPC, subnets, firewall, NAT)
   ↓
3. Terraform: Compute (Juice Shop and/or crAPI VMs)
   ↓
4. Terraform: BIG-IP Config (renders AS3 with backend IPs from compute state, uploads to GCS)
   ↓
5. Terraform: BIG-IP Base (BIG-IP VM polls the AS3 declaration from GCS on boot)
   ↓
6. Terraform: F5 XC (HTTP LB + WAF; origin = BIG-IP public IP from bigip-base state)
```

The bigip-config module renders the AS3 declaration with backend pool IPs from compute remote state, then uploads to `gs://<bucket>/artifacts/uc1/as3/awaf-declaration.json`. The BIG-IP polls GCS during onboarding and applies the configuration locally; no runner-to-BIG-IP connectivity is required. The AS3 apply is idempotent via a sentinel file on the BIG-IP.

Destroy operations run in reverse: `XC → BIG-IP Base → BIG-IP Config → Compute → Infra`.

## Prerequisites

### GCP

1. GCP project with billing enabled.
2. APIs enabled: Compute Engine, Cloud Resource Manager, Cloud Storage, IAM Service Account Credentials.
3. Pre-create the Terraform state bucket. UC1's deploy workflow names it `<project_prefix>-state-bucket` and expects it to already exist with versioning and public-access-prevention enabled (this lets the deploy SA stay bucket-scoped on storage):
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
   - **Runtime SA** - attached to BIG-IP and to the vulnerable-app VMs.

#### Deploy SA roles

| Role | Scope | Why |
|------|-------|-----|
| `roles/compute.networkAdmin` | project | VPC, subnets, router, NAT (infra module). |
| `roles/compute.securityAdmin` | project | Firewall rules (infra module). |
| `roles/compute.instanceAdmin.v1` | project | BIG-IP VM + vulnerable-app VMs (bigip-base, compute modules). |
| `roles/storage.admin` | **bucket** (`<project_prefix>-state-bucket`) | Read/write state objects and the AS3 declaration artifact under that bucket. Bind on the bucket only, not project-wide. |
| `roles/iam.serviceAccountUser` | **runtime SA only** | Lets the deploy SA attach the runtime SA to BIG-IP and to the vulnerable-app VMs. Do not grant this project-wide. |
| `roles/iam.workloadIdentityUser` | deploy SA itself (via principalSet) | WIF binding so the GitHub OIDC token can assume the deploy SA. |

#### Runtime SA roles (attached to BIG-IP and the vulnerable-app VMs)

| Role | Scope | Why |
|------|-------|-----|
| `roles/logging.logWriter` | project | VM telemetry to Cloud Logging. |
| `roles/monitoring.metricWriter` | project | VM telemetry to Cloud Monitoring. |
| `roles/storage.objectViewer` | **bucket** (`<project_prefix>-state-bucket`) | BIG-IP polls the AS3 declaration from `gs://<bucket>/artifacts/uc1/as3/` on boot. Bucket-scoped read is enough. |

#### Binding commands

```bash
PROJECT=<project-id>
PREFIX=<project_prefix>
BUCKET=$PREFIX-state-bucket
DEPLOY_SA=<deploy-sa>@$PROJECT.iam.gserviceaccount.com
RUNTIME_SA=<runtime-sa>@$PROJECT.iam.gserviceaccount.com

# Deploy SA - project-scoped
for ROLE in roles/compute.networkAdmin roles/compute.securityAdmin \
            roles/compute.instanceAdmin.v1; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:$DEPLOY_SA" --role="$ROLE"
done

# Deploy SA - bucket-scoped storage admin
gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
  --member="serviceAccount:$DEPLOY_SA" --role="roles/storage.admin"

# Deploy SA - allowed to act-as the runtime SA only
gcloud iam service-accounts add-iam-policy-binding "$RUNTIME_SA" \
  --member="serviceAccount:$DEPLOY_SA" --role="roles/iam.serviceAccountUser"

# Runtime SA - VM telemetry
for ROLE in roles/logging.logWriter roles/monitoring.metricWriter; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:$RUNTIME_SA" --role="$ROLE"
done

# Runtime SA - read AS3 artifact from state bucket
gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
  --member="serviceAccount:$RUNTIME_SA" --role="roles/storage.objectViewer"
```

5. Workload Identity Pool + Provider for GitHub Actions (see [GitHub Secrets Setup](#github-secrets-setup)).
6. Regional quotas: 8 vCPU minimum (BIG-IP `n2-highmem-4` = 4 vCPU plus the small app VMs), 3 external IPs, 150 GB persistent disk SSD.

### F5 BIG-IP

- F5 BIG-IP PAYG image in `projects/f5-7626-networks-public/global/images/`. An example tag ships in `config/uc1/gcp/env.example.json`.
- The image's PAYG license must cover ASM provisioning at `nominal`.

### F5 Distributed Cloud

- XC tenant with API access enabled.
- API certificate (`.p12`) and password.
- A custom domain you control for `app_domain` (XC also supports tenant-provided domains).

### GitHub repository

- Repository forked with Actions enabled.
- Branches:
  - `deploy-adsp-uc1` - validate + plan + apply
  - `test-adsp-uc1` - validate only
  - `destroy-adsp-uc1` - destroy workflow

## GitHub Secrets Setup

`Settings → Secrets and variables → Actions → New repository secret`:

| Secret | Value |
|--------|-------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/<num>/locations/global/workloadIdentityPools/<pool>/providers/<provider>` |
| `GCP_SERVICE_ACCOUNT` | deploy service account email |
| `VES_P12_CONTENT` | `base64 -w 0 api.p12` output |
| `VES_P12_PASSWORD` | password for the `.p12` |

Optional:

| Secret | When needed |
|--------|-------------|
| `SSH_PUB` | SSH public key for BIG-IP + compute VMs. If unset, BIG-IP falls back to `config/common/ssh/demo_bigip.pub` and the compute VMs use an auto-generated key only. |

All secret values are the file contents (PEM body / base64 blob), not file paths.

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

`GCP_WORKLOAD_IDENTITY_PROVIDER` secret value:
`projects/$PROJECT_NUM/locations/global/workloadIdentityPools/$POOL/providers/$PROVIDER`

## Repository structure

```
F5-ADSP-Automation/
├── .github/workflows/
│   ├── deploy-adsp-uc1-gcp.yml       # Main deployment workflow
│   ├── destroy-adsp-uc1-gcp.yml      # Destroy workflow
│   └── pr_tf_validate.yml            # PR validation
├── config/
│   ├── common/
│   │   ├── gcp/env.json              # Shared GCP settings
│   │   └── ssh/demo_bigip.pub        # SSH public key (BIG-IP + compute)
│   └── uc1/
│       ├── gcp/env.json              # UC1 compute + BIG-IP config
│       └── xc/env.json               # UC1 XC config
├── infra/gcp/                        # VPC, subnets, firewall, NAT
├── compute/gcp/                      # Juice Shop + crAPI VMs
├── f5/
│   ├── bigip-base/gcp/               # BIG-IP instance
│   ├── bigip-config/                 # AS3 declaration + GCS upload (template at config/uc1-config.json)
│   └── xc/                           # F5 Distributed Cloud (shared module)
└── docs/ADSP-UC1-GCP.md              # This document
```

### Terraform state layout

Remote state lives in `gs://<project_prefix>-state-bucket/`:

- `state/uc1/infra/` - VPC, subnets, firewall rules
- `state/uc1/compute/` - Application VMs
- `state/uc1/bigip-config/` - AS3 declaration metadata
- `state/uc1/bigip-base/` - BIG-IP instance
- `state/uc1/xc/` - F5 Distributed Cloud resources
- `artifacts/uc1/as3/` - AS3 declaration the BIG-IP polls

## Configuration

Three files drive UC1. Copy each `env.example.json` to `env.json` and edit only what's called out; the rest of the example values are correct for UC1 and should not be changed unless you're tuning specific behavior.

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

- `admin_src_addr`: JSON array of quoted CIDR strings. Each entry must include the prefix (`/32` for a single host). Bare IPs and unquoted values fail JSON parsing in the infra job.
- `tf_state_bucket`: leave empty. The workflow derives it as `<project_prefix>-state-bucket`.

### UC1 GCP / compute / BIG-IP (`config/uc1/gcp/env.json`)

The example file pre-enables `features.bigip` and sets:

- **compute**: `e2-micro` VMs, 10 GB disks. `vm_create_crapi: true`, `vm_create_juice_shop: false` by default. Flip the second flag if you want both apps.
- **bigip_base**: PAYG `n2-highmem-4` image pinned to a known-good tag, single-NIC, ASM at `nominal`.
- **bigip_config**: `backend_compute: "true"` so the AS3 renderer pulls backend pool IPs from compute remote state.

The one field you must set is:

```json
{
  "compute": {
    "gcp_runtime_service_account_email": "<runtime-sa>@<project-id>.iam.gserviceaccount.com"
  }
}
```

That SA is attached to the compute VMs and to the BIG-IP. The deploy SA must hold `iam.serviceAccountUser` on it.

Do not change:

- `bigip_base.nic_count: "false"` - single-NIC architecture.
- `features.bigip: true` - required.

### XC (`config/uc1/xc/env.json`)

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

Fields that stay at the example default for UC1:

- `backend_bigip: true`, `origin_server: ""` - origin pool resolves the BIG-IP public IP from `state/uc1/bigip-base`.
- `xc_waf_blocking: true`
- Feature toggles in `xc_features` are all `false`; flip individual flags for the demo being staged. The full surface is in [f5/xc/variables.tf](../f5/xc/variables.tf).

## Deployment Procedures

### Initial deploy

1. Fork the repo.
2. Edit the three config files in `config/`.
3. Set GitHub Secrets.
4. Push your edits to your default branch.
5. Cut and push the deploy branch:
   ```bash
   git checkout -b deploy-adsp-uc1 && git push -u origin deploy-adsp-uc1
   ```
6. Watch the workflow in the Actions tab.

### Validation only

```bash
git checkout -b test-adsp-uc1 && git push -u origin test-adsp-uc1
```

Runs `terraform validate` for every module; skips plan and apply.

### Update an existing deployment

1. Edit config on the default branch.
2. Merge or push to `deploy-adsp-uc1`. The workflow re-runs plan + apply.

### Destroy

```bash
git checkout -b destroy-adsp-uc1 && git push -u origin destroy-adsp-uc1
```

Destroy order: XC → BIG-IP Base → BIG-IP Config → Compute → Infra. The state bucket is not deleted by the workflow since it was created out of band; remove it manually when you're done.

## Accessing deployment outputs

```bash
BUCKET="<project_prefix>-state-bucket"

# BIG-IP management IP + admin password
gsutil cat gs://$BUCKET/state/uc1/bigip-base/default.tfstate \
  | jq -r '.outputs.bigip_public_ip.value, .outputs.bigip_admin_password.value'

# App backends
gsutil cat gs://$BUCKET/state/uc1/compute/default.tfstate \
  | jq -r '.outputs.juice_shop_internal_ip.value, .outputs.crapi_internal_ip.value'

# XC public endpoint
gsutil cat gs://$BUCKET/state/uc1/xc/default.tfstate \
  | jq -r '.outputs.endpoint.value'
```

### Key outputs reference

| Output | Module | Description |
|--------|--------|-------------|
| `bigip_public_ip` | bigip-base | BIG-IP management / data plane public IP |
| `bigip_mgmt_internal_ip` | bigip-base | BIG-IP internal IP |
| `bigip_admin_password` | bigip-base | Generated admin password (sensitive) |
| `juice_shop_internal_ip` | compute | Juice Shop VM internal IP |
| `crapi_internal_ip` | compute | crAPI VM internal IP |
| `endpoint` | xc | XC application domain (public URL) |
| `xc_lb_name` | xc | XC LoadBalancer resource name |
| `xc_waf_name` | xc | XC WAF policy name |

## Verification and Testing

### BIG-IP management access

```bash
MGMT_IP=$(gsutil cat gs://$BUCKET/state/uc1/bigip-base/default.tfstate \
  | jq -r '.outputs.bigip_public_ip.value')
ADMIN_PASSWORD=$(gsutil cat gs://$BUCKET/state/uc1/bigip-base/default.tfstate \
  | jq -r '.outputs.bigip_admin_password.value')

echo "GUI: https://$MGMT_IP"
echo "User: admin"
echo "Password: $ADMIN_PASSWORD"
```

SSH:

```bash
ssh -i <private-key> admin@$MGMT_IP
```

If `SSH_PUB` is set, use the matching private key. Otherwise BIG-IP uses the committed `demo_bigip.pub`; compute VMs are reachable only via the auto-generated key surfaced as the Terraform output `private_key`.

### Application reachability

```bash
curl -k "https://$MGMT_IP/"

ENDPOINT=$(gsutil cat gs://$BUCKET/state/uc1/xc/default.tfstate \
  | jq -r '.outputs.endpoint.value')
curl "https://$ENDPOINT/"
```

### BIG-IP health

```bash
ssh admin@$MGMT_IP
tmsh show ltm virtual
tmsh show ltm pool members

curl -sku admin:"$ADMIN_PASSWORD" \
  https://localhost:8443/mgmt/shared/appsvcs/declare | jq
```

### XC verification

In the XC console:

1. `Administration → Namespaces`: confirm `xc_namespace` exists.
2. `Multi-Cloud App Connect → HTTP Load Balancers → <your LB>`: confirm the origin pool member matches the BIG-IP public IP and is healthy.
3. Send live traffic and check `Security → Security Events` for WAF activity.

## Troubleshooting

**`jq: parse error: Invalid numeric literal` in the infra job.**
Your `admin_src_addr` (or another CIDR/list field) has unquoted values. JSON requires `["1.2.3.4/32"]`, not `[1.2.3.4/32]`.

**Bootstrap job fails with `Required "storage.buckets.create" permission` or similar storage error.**
The deploy SA's storage role is bucket-scoped, so the bucket must exist before the workflow runs. Pre-create it with the gcloud commands in [Prerequisites → GCP](#gcp).

**`The user does not have access to service account "<runtime-sa>"` during compute or bigip-base apply.**
The deploy SA needs `roles/iam.serviceAccountUser` on the runtime SA email set in `config/uc1/gcp/env.json` (`compute.gcp_runtime_service_account_email`). Bind on the runtime SA only, not project-wide.

**BIG-IP boots but the AS3 declaration is not applied.**
- Confirm the AS3 declaration is in GCS: `gsutil ls gs://$BUCKET/artifacts/uc1/as3/`.
- SSH to the BIG-IP and check `/var/log/cloud/as3-pull-apply.log`.
- The onboarding template retries `pull_and_apply_as3_from_gcs`; transient failures should self-heal.
- The runtime SA attached to the BIG-IP needs `roles/storage.objectViewer` on the state bucket. See [Runtime SA roles](#runtime-sa-roles-attached-to-big-ip-and-the-vulnerable-app-vms).

**Pool members show offline in BIG-IP.**
- `gcloud compute instances list` to confirm the VMs are up.
- Internal firewall rules must allow the BIG-IP subnet to reach the app subnet.
- `tmsh show ltm pool members detail` on the BIG-IP.

**BIG-IP management unreachable.**
- `admin_src_addr` in `config/common/gcp/env.json` must include the IP you're testing from.
- Firewall must allow TCP 22, 443, 8443 from `admin_src_addr` to the management interface.
- Serial console:
  ```bash
  gcloud compute instances get-serial-port-output <bigip-vm> --project=$PROJECT --zone=$ZONE
  ```

**XC origin shows down / `https://<app_domain>` returns 502.**
- The BIG-IP public IP must be reachable from the public internet. Confirm direct `curl https://<bigip_public_ip>/` succeeds before suspecting XC.
- `app_domain` in `config/uc1/xc/env.json` should match the FQDN the BIG-IP virtual server serves.

**`VES_P12_CONTENT` / `VES_P12_PASSWORD` errors.**
Verify `VES_P12_CONTENT` decodes back to a valid `.p12`:
```bash
echo "$VES_P12_CONTENT" | base64 -d > /tmp/test.p12
openssl pkcs12 -info -in /tmp/test.p12 -nokeys
```

**Quota exceeded.**
- Request quota increase under `IAM & Admin → Quotas`.
- Or shrink `bigip_base.machine_type` (minimum `n2-highmem-4`).

## Operations

- Restrict `admin_src_addr` to known IP ranges and protect the `deploy-adsp-uc1` / `destroy-adsp-uc1` branches with branch protection rules.
- State files should not be edited by hand. Back up state before major changes:
  ```bash
  gsutil -m cp -r gs://$BUCKET/state/uc1 gs://backup-bucket/state-uc1-$(date +%Y%m%d)
  ```
- Destroy environments when idle. BIG-IP PAYG dominates the hourly cost.

## Cost estimates (us-west1, defaults)

| Component | Instance Type | Hours/Month | Est. Cost/Month |
|-----------|---------------|-------------|-----------------|
| BIG-IP PAYG | n2-highmem-4 | 730 | ~$350 |
| Compute VM (crAPI) | e2-micro | 730 | ~$7 |
| Compute VM (Juice Shop) | e2-micro | 730 | ~$7 |
| External IPs (3x) | Standard | 730 | ~$22 |
| Persistent disks | SSD + Standard | - | ~$20 |
| Network egress | variable | - | ~$10 |
| **Total (GCP)** | | | **~$416/mo** |
| F5 Distributed Cloud | - | - | per subscription |

Reduce cost by destroying when idle, disabling one of the two vulnerable apps, and shrinking disks where possible.
