# F5 Application Delivery and Security Platform Automation

CI/CD-driven deployment of F5 Application Delivery and Security Platform (ADSP) use cases. Each use case provisions its own complete infrastructure build via Terraform and GitHub Actions, with state stored in Google Cloud Storage. Use cases are deployed one at a time and do not share live infrastructure.

## Use cases

| ID | Description | Cloud | Guide |
|----|-------------|-------|-------|
| UC1 | BIG-IP with AWAF fronting vulnerable applications, F5 Distributed Cloud HTTP LB with WAF on top | GCP | [Deploy UC1 in Google Cloud](docs/ADSP-UC1-GCP.md) |
| UC2 | NGINX Ingress Controller with NGINX App Protect on GKE, NGINX One for fleet management, F5 Distributed Cloud with API security on top | GCP | [Deploy UC2 in Google Cloud](docs/ADSP-UC2-GCP.md) |

Pick a use case and follow its deployment guide.

## Repository layout

- `infra/<cloud>/` — shared per-cloud networking
- `compute/<cloud>/` — application VMs (UC1)
- `k8s/<cloud>/` — Kubernetes cluster (UC2)
- `f5/bigip-base/<cloud>/`, `f5/bigip-config/<cloud>/` — BIG-IP instance and AS3 declaration (UC1)
- `f5/nic/<cloud>/` — NGINX Ingress Controller and App Protect (UC2)
- `f5/xc/` — F5 Distributed Cloud, cloud-agnostic, shared across use cases
- `apps/` — application manifests referenced by use cases
- `config/common/<cloud>/` — shared cloud config
- `config/uc<N>/<cloud-or-xc>/` — per-UC config
- `.github/workflows/` — deploy and destroy workflows per UC
- `docs/` — per-UC deployment guides

## Conventions

- State lives at `state/uc<N>/<module>/` in the shared state bucket. Artifacts (AS3 declarations, NAP policy bundles, etc.) live at `artifacts/uc<N>/`.
- Branches drive workflow runs:
  - `deploy-adsp-uc<N>` runs validate, plan, apply
  - `test-adsp-uc<N>` runs validate only
  - `destroy-adsp-uc<N>` runs the destroy workflow in reverse module order
- Terraform modules are shared across use cases. Feature flags in each UC's config select which resources get created.

## Requirements

- A GCP project with billing enabled and Workload Identity Federation configured for GitHub Actions
- An F5 Distributed Cloud tenant with an API certificate
- GitHub Actions enabled on the forked repository

Per-UC quotas, IAM roles, and configuration are documented in each use case guide.
