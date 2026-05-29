# Deploy Use-Case 1 in Google Cloud

This document provides complete instructions for deploying Application Security and Delivery Portfolio (ADSP) Use-Case 1 in Google Cloud Platform.

---

## Overview

This repository deploys a multi-tier security demonstration environment consisting of:

- **Network Infrastructure** - VPC with segmented subnets (management, external, internal, application)
- **Vulnerable Applications** - OWASP Juice Shop and crAPI running on Docker
- **F5 BIG-IP** - Application Delivery Controller with Advanced Web Application Firewall (single-NIC configuration)
- **F5 Distributed Cloud (XC)** - Cloud-native application security and delivery

The deployment is orchestrated entirely through GitHub Actions using Terraform with GCS remote state. Local execution is not supported.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ F5 Distributed Cloud (XC)                                   │
│ ├─ HTTP Load Balancer                                       │
│ ├─ WAF Policy                                               │
│ └─ Origin: BIG-IP Public IP                                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ GCP VPC (crafty-vpc-*)                                      │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ F5 BIG-IP (Single-NIC)                               │  │
│  │ ├─ Management GUI/SSH (Public IP)                    │  │
│  │ ├─ AS3 Configuration (AWAF)                          │  │
│  │ └─ Pool Members: Juice Shop, crAPI                   │  │
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

### Deployment Flow

The GitHub Actions workflow deploys modules sequentially with dependencies:

```
1. Bootstrap State Bucket (GCS)
   ↓
2. Terraform: Infra (VPC, subnets, firewall, NAT)
   ↓
3. Terraform: Compute (Juice Shop, crAPI VMs)
   ↓
4. Terraform: BIG-IP Config (Uploads AS3 declaration to GCS)
   ↓
5. Terraform: BIG-IP Base (F5 BIG-IP instance that pulls AS3 from GCS on boot)
   ↓
6. Terraform: F5 XC (Distributed Cloud config)
```

**AS3 Configuration Flow:**
- BIG-IP Config module renders AS3 declaration with backend pool IPs from compute remote state
- Declaration is uploaded to GCS at `gs://{state-bucket}/artifacts/uc1/as3/awaf-declaration.json`
- BIG-IP polls GCS and applies configuration locally (no runner-to-BIG-IP connectivity required)
- Configuration is applied once after AS3 extension is ready (idempotent via sentinel file)

Destroy operations run in reverse order: `XC → BIG-IP Base → Compute → Infra → State Bucket`

---

## Prerequisites

### GCP Requirements

1. **GCP Project** with billing enabled
2. **Required APIs enabled:**
   - Compute Engine API
   - Cloud Resource Manager API
   - Cloud Storage API
   - IAM Service Account Credentials API
3. **Service Account** with the following roles:
   - `roles/compute.admin`
   - `roles/storage.admin`
   - `roles/iam.serviceAccountUser`
4. **Workload Identity Pool** configured for GitHub Actions federation
5. **Sufficient Quotas:**
   - CPUs: 8+ (for BIG-IP n2-highmem-4)
   - External IP addresses: 3+
   - Persistent disk SSD: 150+ GB

### F5 Distributed Cloud (XC) Requirements

1. **XC Tenant** with API access enabled
2. **API Certificate** (.p12 file) with password
3. **Namespace** - Automatically created by Terraform
4. **Custom Domain** configured (optional, or use XC-provided domain)

### GitHub Repository Requirements

1. **Forked Repository** with Actions enabled
2. **Protected Branches:**
   - `deploy-adsp-uc1` - Triggers validation + deployment
   - `test-adsp-uc1` - Triggers validation only
   - `destroy-adsp-uc1` - Triggers destroy workflow
3. **GitHub Secrets** (see Configuration section)

---

## Repository Structure

```
crafty-corgi/
├── .github/workflows/
│   ├── deploy-adsp-uc1-gcp.yml      # Main deployment workflow
│   ├── destroy-adsp-uc1-gcp.yml     # Destroy workflow
│   └── pr_tf_validate.yml           # PR validation
├── config/
│   ├── common/
│   │   ├── gcp/env.json             # Shared GCP settings
│   │   └── ssh/demo_bigip.pub       # SSH public key (shared: BIG-IP + compute)
│   └── uc1/
│       ├── gcp/env.json             # Use-case 1 GCP config
│       └── xc/env.json              # Use-case 1 XC config
├── infra/gcp/                       # Network infrastructure
│   ├── main.tf
│   ├── vpc.tf
│   ├── firewall.tf
│   ├── variables.tf
│   └── outputs.tf
├── compute/gcp/                     # Application VMs
│   ├── main.tf
│   ├── instance.tf
│   ├── variables.tf
│   └── outputs.tf
├── f5/
│   ├── bigip-base/gcp/              # BIG-IP instance
│   │   ├── bigip.tf
│   │   ├── templates/f5_onboard.tmpl
│   │   └── outputs.tf
│   ├── bigip-config/gcp/             # BIG-IP AS3 config
│   │   ├── bigip-config.tf
│   │   └── config/awaf-config.json
│   └── xc/                          # F5 Distributed Cloud
│       ├── main.tf
│       ├── namespace.tf
│       ├── locals.tf
│       └── outputs.tf
└── docs/
    └── ADSP-UC1-GCP.md              # This document
```

### Terraform State Layout

Remote state is stored in GCS bucket `${project_prefix}-state-bucket`:

- `state/infra/` - VPC, subnets, firewall rules
- `state/compute/` - Application VMs
- `state/bigip-base/` - BIG-IP instance
- `state/bigip-config/` - BIG-IP AS3 configuration metadata
- `state/xc/` - F5 Distributed Cloud resources
- `artifacts/uc1/as3/` - AS3 declarations for BIG-IP to pull (uploaded by bigip-config module)

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
- `gcp_project_id` - GCP project ID
- `gcp_region` - Target GCP region
- `gcp_zone` - Target GCP zone (must be inside `gcp_region`)
- `project_prefix` - Unique prefix for resource naming (lowercase, alphanumeric)
- `resource_owner` - Initials or identifier used for resource labels
- `admin_src_addr` - Public IP CIDRs allowed to reach management interfaces (array of CIDRs)

**Leave as-is:**
- `tf_state_bucket` - Auto-generated as `${project_prefix}-state-bucket`

### Step 2: Configure Use-Case Settings

Edit `config/uc1/gcp/env.json`:

```json
{
  "compute": {
    "gcp_runtime_service_account_email": "your-service-account@PROJECT.iam.gserviceaccount.com",
    "machine_type": "e2-micro",
    "boot_disk_gb": 10,
    "vm_create_crapi": true,
    "vm_create_juice_shop": false
  },
  "bigip_base": {
    "image_name": "projects/f5-7626-networks-public/global/images/f5-bigip-17-1-2-0-0-8-payg-better-25mbps-241121080429",
    "machine_type": "n2-highmem-4",
    "f5_username": "admin",
    "nic_count": "false",
    "asm": "nominal",
    "apm": "none"
  },
  "bigip_config": {
    "backend_compute": "true"
  },
  "features": {
    "bigip": true
  }
}
```

**Required Changes:**
- `compute.gcp_runtime_service_account_email` - Service account for VM runtime

**Customizable Settings:**
- `vm_create_crapi` / `vm_create_juice_shop` - Enable/disable specific vulnerable apps
- `bigip_base.machine_type` - BIG-IP instance size (minimum: n2-highmem-4)
- `bigip_base.asm` - ASM provisioning level: `none`, `nominal`, `minimum`, `dedicated`

**Do Not Modify:**
- `nic_count: "false"` - Single-NIC architecture (hardcoded)
- `features.bigip: true` - Required for BIG-IP deployment

### Step 3: Configure F5 XC Settings

Edit `config/uc1/xc/env.json`:

```json
{
  "xc_base": {
    "xc_tenant": "your-xc-tenant",
    "api_url": "https://your-tenant.console.ves.volterra.io/api",
    "xc_namespace": "your-namespace",
    "app_domain": "your-app.example.com",
    "origin_server": "",
    "origin_port": "80",
    "backend_bigip": true,
    "xc_waf_blocking": true
  },
  "xc_features": {
    "xc_api_disc": false,
    "xc_bot_def": false,
    "xc_ddos_pro": false
  }
}
```

**Required Changes:**
- `xc_tenant` - XC tenant name
- `api_url` - XC tenant API URL
- `xc_namespace` - Namespace to create (cannot be `system` or `shared`)
- `app_domain` - Public domain for application access

**Notes:**
- `xc_namespace` - Terraform creates this namespace; pick a name unique within the tenant.
- `backend_bigip: true` - XC origin is auto-discovered from BIG-IP remote state.
- `origin_server: ""` - Leave empty; resolved from BIG-IP public IP.
- Toggle entries under `xc_features` per the demo being staged.

---

## GitHub Secrets Setup

Configure the following secrets in GitHub repository settings: `Settings → Secrets and variables → Actions → New repository secret`

### Required Secrets

| Secret Name | Description | How to Obtain |
|-------------|-------------|---------------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Workload Identity Provider resource name | Format: `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_ID/providers/PROVIDER_ID` |
| `GCP_SERVICE_ACCOUNT` | Service account email for GCP authentication | Format: `SERVICE_ACCOUNT_NAME@PROJECT_ID.iam.gserviceaccount.com` |
| `VES_P12_CONTENT` | Base64-encoded XC API certificate (.p12 file) | Run: `base64 -w 0 /path/to/certificate.p12` (Linux) or `base64 -i /path/to/certificate.p12` (macOS) |
| `VES_P12_PASSWORD` | Password for XC API certificate | Provided when downloading certificate from XC console |

### Optional Secrets

| Secret Name | Description | When Needed |
|-------------|-------------|-------------|
| `SSH_PUB` | SSH public key for BIG-IP and compute VMs (if not using committed key) | Alternative to `config/common/ssh/demo_bigip.pub`. If set, used for both BIG-IP and compute VM SSH access. If not set, BIG-IP falls back to committed key; compute VMs use auto-generated key only. |

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
   - `config/uc1/gcp/env.json`
   - `config/uc1/xc/env.json`
3. **Set GitHub Secrets** (see GitHub Secrets Setup)
4. **Commit and push changes** to `main` branch
5. **Create deployment branch:**
   ```bash
   git checkout -b deploy-adsp-uc1
   git push origin deploy-adsp-uc1
   ```
6. **Monitor workflow execution** in GitHub Actions tab
7. **Retrieve outputs** (see Accessing Deployment Outputs)

### Validation-Only Testing

To validate Terraform without applying:

```bash
git checkout -b test-adsp-uc1
git push origin test-adsp-uc1
```

This triggers validation for all modules but skips `terraform apply` steps.

### Updating Existing Deployment

1. Make configuration changes on `main` branch
2. Merge or push to `deploy-adsp-uc1` branch
3. Workflow will automatically plan and apply changes

### Destroying Infrastructure

**WARNING:** This permanently deletes all resources including the state bucket.

```bash
git checkout -b destroy-adsp-uc1
git push origin destroy-adsp-uc1
```

Destroy sequence:
1. F5 XC resources
2. BIG-IP Base instance
3. Compute VMs
4. Network infrastructure
5. GCS state bucket (including all history)

---

## Accessing Deployment Outputs

### Via GCP Cloud Shell

Activate Cloud Shell in GCP Console, then:

```bash
PROJECT_PREFIX="your-prefix"
STATE_BUCKET="${PROJECT_PREFIX}-state-bucket"

# Get BIG-IP management IP
gsutil cat gs://${STATE_BUCKET}/state/bigip-base/default.tfstate | \
  jq -r '.outputs.bigip_public_ip.value'

# Get BIG-IP admin password (sensitive)
gsutil cat gs://${STATE_BUCKET}/state/bigip-base/default.tfstate | \
  jq -r '.outputs.bigip_admin_password.value'

# Get XC application domain
gsutil cat gs://${STATE_BUCKET}/state/xc/default.tfstate | \
  jq -r '.outputs.endpoint.value'

# Get application internal IPs
gsutil cat gs://${STATE_BUCKET}/state/compute/default.tfstate | \
  jq -r '.outputs.juice_shop_internal_ip.value'
gsutil cat gs://${STATE_BUCKET}/state/compute/default.tfstate | \
  jq -r '.outputs.crapi_internal_ip.value'
```

### Via GitHub Actions Workflow Outputs

Add a custom step to the workflow to output values:

```yaml
- name: Show BIG-IP Access Info
  working-directory: ./f5/bigip-base/gcp
  run: |
    echo "BIG-IP Management IP: $(terraform output -raw bigip_public_ip)"
    echo "BIG-IP Username: admin"
    echo "Access GUI: https://$(terraform output -raw bigip_public_ip):443"
```

### Key Outputs Reference

| Output | Module | Description |
|--------|--------|-------------|
| `bigip_public_ip` | bigip-base | BIG-IP management/data plane public IP |
| `bigip_mgmt_internal_ip` | bigip-base | BIG-IP internal IP address |
| `bigip_admin_password` | bigip-base | Generated admin password (sensitive) |
| `juice_shop_internal_ip` | compute | Juice Shop VM internal IP |
| `crapi_internal_ip` | compute | crAPI VM internal IP |
| `endpoint` | xc | XC application domain (public URL) |
| `xc_lb_name` | xc | XC load balancer resource name |
| `xc_waf_name` | xc | XC WAF policy name |

---

## Verification and Testing

### BIG-IP Management Access

1. **Retrieve credentials:**
   ```bash
   MGMT_IP=$(gsutil cat gs://${STATE_BUCKET}/state/bigip-base/default.tfstate | \
     jq -r '.outputs.bigip_public_ip.value')
   ADMIN_PASSWORD=$(gsutil cat gs://${STATE_BUCKET}/state/bigip-base/default.tfstate | \
     jq -r '.outputs.bigip_admin_password.value')
   ```

2. **Access GUI:**
   - URL: `https://${MGMT_IP}:443`
   - Username: `admin`
   - Password: `${ADMIN_PASSWORD}`

3. **SSH Access (BIG-IP):**
   ```bash
   ssh -i /path/to/private/key admin@${MGMT_IP}
   ```

4. **SSH Access (Compute VMs):**
   If `SSH_PUB` secret is configured, SSH to compute VMs using the corresponding private key:
   ```bash
   ssh -i /path/to/private/key adminuser@${COMPUTE_IP}
   ```
   If no `SSH_PUB` is set, use the Terraform-generated private key from `terraform output -raw private_key`.

### Application Access

1. **Via BIG-IP Virtual Server:**
   ```bash
   curl -H "Host: your-app.local" http://${MGMT_IP}
   ```

2. **Via F5 Distributed Cloud:**
   ```bash
   curl https://your-app.example.com
   ```

### Health Checks

**BIG-IP Pool Status:**
```bash
# SSH to BIG-IP
ssh admin@${MGMT_IP}

# Check virtual server status
tmsh show ltm virtual

# Check pool member health
tmsh show ltm pool members

# View AS3 declarations
curl -sku admin:${ADMIN_PASSWORD} https://localhost:8443/mgmt/shared/appsvcs/declare | jq
```

**Application Connectivity:**
```bash
# From BIG-IP, test backend connectivity
curl http://JUICE_SHOP_INTERNAL_IP
curl http://CRAPI_INTERNAL_IP:8888
```

**XC Configuration:**
1. Login to XC Console: `https://your-tenant.console.ves.volterra.io`
2. Verify namespace was created: `Administration → Namespaces` 
3. Navigate to: `Load Balancers → HTTP Load Balancers`
4. Verify load balancer shows healthy origin
5. Test application via public domain

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
- Verify service account has `roles/compute.admin` and `roles/storage.admin`
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
  gsutil ls gs://${STATE_BUCKET}/state/MODULE_NAME/default.tflock
  gsutil rm gs://${STATE_BUCKET}/state/MODULE_NAME/default.tflock
  ```

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
- Verify `api_url` in `config/uc1/xc/env.json` matches tenant
- Check API certificate is not expired in XC console

### Terraform Variable Errors

**Error:** `No value for required variable`

**Resolution:**
- Verify all required fields are set in `env.json` files
- Check workflow logs for variable generation step
- Validate JSON syntax: `jq . config/uc1/gcp/env.json`

### BIG-IP Deployment Issues

**Error:** BIG-IP instance boots but management unreachable

**Resolution:**
- Verify `admin_src_addr` in `config/common/gcp/env.json` includes your public IP
- Check firewall rules allow TCP 22, 443, 8443 to management interface
- Review serial console output:
  ```bash
  gcloud compute instances get-serial-port-output INSTANCE_NAME \
    --project=PROJECT_ID --zone=ZONE
  ```

**Error:** Pool members show offline in BIG-IP

**Resolution:**
- Verify backend VMs are running: `gcloud compute instances list`
- Check internal firewall rules allow BIG-IP subnet to app subnet
- Verify AS3 configuration applied successfully
- SSH to BIG-IP: `tmsh show ltm pool members detail`

### Quota Exceeded Errors

**Error:** `Quota 'CPUS' exceeded. Limit: X in region Y`

**Resolution:**
- Request quota increase in GCP Console: `IAM & Admin → Quotas`
- Reduce BIG-IP instance size in `config/uc1/gcp/env.json` (minimum: n2-highmem-4)
- Use preemptible instances for compute VMs (not recommended for BIG-IP)

---

## Operations

Restrict `admin_src_addr` in `config/common/gcp/env.json` to known IP ranges, and apply branch protection to `deploy-adsp-uc1` and `destroy-adsp-uc1` before using this in any environment that matters.

State files should not be edited by hand. Back up state before major changes:

```bash
gsutil -m cp -r gs://${STATE_BUCKET}/state gs://backup-bucket/state-$(date +%Y%m%d)
```

Destroy environments when idle. BIG-IP PAYG dominates the hourly cost. See [Cost Estimates](#cost-estimates).

---

## Cost Estimates

Estimated monthly costs for `us-west1` region (as of 2026):

| Component | Instance Type | Hours/Month | Est. Cost/Month |
|-----------|---------------|-------------|-----------------|
| BIG-IP PAYG | n2-highmem-4 | 730 | ~$350 |
| Compute VM (crAPI) | e2-micro | 730 | ~$7 |
| Compute VM (Juice Shop) | e2-micro | 730 | ~$7 |
| External IPs (3x) | Standard | 730 | ~$22 |
| Persistent Disks | SSD + Standard | - | ~$20 |
| Network Egress | Variable | - | ~$10 |
| **Total (GCP)** | | | **~$416/month** |
| F5 Distributed Cloud | - | - | Contact F5 Sales |

**Cost Reduction Options:**
- Destroy infrastructure when not in use (demo environments)
- Use regional IPs instead of external IPs (requires NAT configuration)
- Reduce persistent disk sizes
- Use standard disks instead of SSD for non-BIG-IP resources

**Note:** F5 XC pricing varies based on usage, features, and contract terms. Contact F5 for detailed pricing.

---

## Additional Resources

### F5 Documentation

- [F5 BIG-IP Terraform Module](https://registry.terraform.io/modules/F5Networks/bigip-module/gcp)
- [AS3 User Guide](https://clouddocs.f5.com/products/extensions/f5-appsvcs-extension/latest/)
- [BIG-IP Cloud Edition](https://clouddocs.f5.com/cloud/public/v1/)
- [F5 Distributed Cloud Documentation](https://docs.cloud.f5.com/)

### GCP Documentation

- [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [VPC Networking](https://cloud.google.com/vpc/docs)
- [Compute Engine](https://cloud.google.com/compute/docs)

### Terraform Documentation

- [Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
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

This project uses F5 BIG-IP PAYG licensing (included in hourly compute cost) and F5 Distributed Cloud services (separate billing). Review F5 licensing terms before deployment.

Terraform modules and configuration are provided as-is for demonstration purposes.

---

**Last Updated:** 2026-02-15
**Terraform Version:** >= 1.3.0
**Target GCP Regions:** All (tested on us-west1)
