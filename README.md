# F5 Application Delivery and Security Platform with CI/CD

This repository demonstrates how the **F5 Application Delivery and Security Platform (ADSP)** from **F5, Inc.** can be deployed using a structured, production-aligned CI/CD workflow.

The project is intentionally designed to be:

- **Forkable**
- **Cloud-native**
- **Modular**
- **Real-world aligned**
- **Automation-first**

This is not a click-through lab.  
This repository shows how ADSP components can be provisioned and composed using Terraform and GitHub Actions in a repeatable deployment pipeline.

## Quick Start

1. **Read the deployment guide:** [Deploy Use-Case 1 in Google Cloud](docs/ADSP-UC1-GCP.md)
2. **Configure settings:**
   - `config/common/gcp/env.json` - GCP project, region, prefix
   - `config/uc1/gcp/env.json` - Use-case specific settings
   - `config/uc1/xc/env.json` - F5 Distributed Cloud config
3. **Set GitHub Secrets** (see deployment guide)
4. **Push to `deploy-adsp-uc1` branch** to deploy

## Architecture

- **Infra:** VPC with segmented subnets (management, external, internal, application)
- **Compute:** Vulnerable applications (OWASP Juice Shop, crAPI)
- **F5 BIG-IP:** Application Delivery Controller with AWAF (single-NIC)
- **F5 Distributed Cloud:** Cloud-native application security and delivery

## Deployment Branches

- `deploy-adsp-uc1` - Validate, plan, and apply infrastructure
- `test-adsp-uc1` - Validate only (no apply)
- `destroy-adsp-uc1` - Destroy all resources

## Documentation

- [Deploy Use-Case 1 in Google Cloud](docs/ADSP-UC1-GCP.md) - Complete deployment guide

## Requirements

- GCP Project with Workload Identity Federation
- F5 Distributed Cloud tenant with API certificate
- GitHub Actions enabled

For detailed prerequisites, configuration, and troubleshooting, see the [deployment guide](docs/ADSP-UC1-GCP.md).
