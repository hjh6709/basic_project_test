# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **personal repository** (`hjh6709/basic_project_test`) for solo reproduction and end-to-end testing of the full Chilseongpa platform — the same infrastructure and application stack as the team project, maintained by one person.

**Chilseongpa** is a hybrid multi-cloud AIOps platform for operating Kubernetes services across GCP (primary/active) and AWS (standby). Key capabilities: Cloudflare-based automatic DNS failover, Prometheus/Grafana observability stack, and LLM-powered incident analysis via a Discord bot + Gemini API.

## Architecture

```
Traffic → Cloudflare Edge (Load Balancer + Health Check)
           ├─→ GCP K3s Cluster (Active) ─→ Cloud SQL (MySQL 8.0)
           └─→ AWS K3s Cluster (Standby)

Monitoring (AWS private subnet):
  Prometheus → Grafana → Alertmanager → Discord Bot → Gemini API
```

**Infrastructure provisioning flow:**

1. `terraform apply` creates all cloud resources and auto-generates `infra/ansible/inventory.ini`
2. `ansible-playbook playbook.yml` configures servers (Node Exporter → K3s → Docker → Monitoring stack)
3. GitHub Actions CI/CD deploys the application to both clusters

**Network:** AWS VPC `10.20.0.0/16` — K3s Standby and Monitoring servers are in the private subnet (`10.20.2.0/24`); access requires Bastion ProxyCommand (auto-configured by `ssh_config_setup.sh`).

**Cloudflare Tunnels:** Three tunnels (GCP, AWS, Monitoring) provide secure egress from private networks. Prometheus scraping uses Cloudflare Access service tokens (Zero Trust).

## Implementation Details

**`cloudflared` is installed automatically via EC2/GCP `user_data`** — Ansible does not install it. The Cloudflare module creates tunnel tokens first, which are then embedded into instance `user_data` scripts at `terraform apply` time. When instances boot, they self-register with Cloudflare. Never attempt to install or restart `cloudflared` via Ansible.

**Cloudflare module must apply before AWS/GCP modules** — `main.tf` passes tunnel tokens from the `cloudflare` module output into the `aws` and `gcp` modules. If you `terraform apply -target` individual modules, always target `module.cloudflare` first.

## Common Commands

### Infrastructure (Terraform)

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars  # Fill in secrets before first run
terraform init
terraform plan
terraform apply
bash ssh_config_setup.sh  # Configure SSH ProxyCommand for private subnet access
```

**Important — module execution order:** The `cloudflare` module runs first (creates tunnels and generates tokens), then passes those tokens into `aws` and `gcp` modules via `user_data`. This dependency is implicit in `main.tf`; do not run modules independently.

**Check Terraform outputs before running Ansible:**

```bash
# Retrieve Cloudflare Access tokens needed for secrets.sh
terraform output cf_access_client_id
terraform output -raw cf_access_client_secret

# Verify IP addresses used by ssh_config_setup.sh
terraform output aws_bastion_public_ip
terraform output aws_k3s_private_ip
terraform output aws_monitoring_private_ip
```

**Destroy all resources:**

```bash
terraform destroy
```

### Server Configuration (Ansible)

```bash
cd infra/ansible
source secrets.sh           # Sets ALERT_WEBHOOK_URL, CF_CLIENT_ID, CF_CLIENT_SECRET
ansible all -m ping         # Verify connectivity
ansible-playbook playbook.yml -e "storage_setup_enabled=false"

# Run only on a specific host group (--limit flag)
ansible-playbook playbook.yml --limit gcp-main
ansible-playbook playbook.yml --limit aws-sub
ansible-playbook playbook.yml --limit aws-monitor
```

**SSH shortcuts** (available after `bash ssh_config_setup.sh`):

```bash
ssh bastion      # AWS Bastion Host (public subnet)
ssh k3s          # AWS K3s Standby node (via Bastion ProxyJump)
ssh monitoring   # AWS Monitoring server (via Bastion ProxyJump)
```

### Application

```bash
# Build backend container
cd application/backend
docker build -t chilseongpa-app .

# Deploy to Kubernetes
kubectl apply -f application/k8s/

# Load testing — inline env vars (quick run)
cd application/k6
TARGET_BASE_URL="https://your-domain.com" TARGET_API_PATH="/api/test" \
  HTTP_METHOD="POST" VUS="100" DURATION="2m" ./run_k6_test.sh

# Load testing — Docker (recommended, uses .env.testk6)
docker build -t chilseongpa-k6 .
docker run --rm --ulimit nofile=65535:65535 --env-file .env.testk6 \
  -v "${PWD}:/work" -w /work chilseongpa-k6 \
  run scenarios/single_api_load.js --dns ttl=0 \
  --summary-export "results/summary_$(date +%Y%m%d_%H%M%S).json"
```

> Set `WANT_503=true` in `.env.testk6` to treat 503 responses as expected (used when intentionally triggering Failover). Results are saved to `application/k6/results/`.

### AIOps Discord Bot

```bash
cd aiops/discord-bot
docker build -t chilseongpa-discord-bot .
# Requires: DISCORD_TOKEN, GEMINI_API_KEY env vars
```

## Key Files

| File                                        | Purpose                                                                         |
| ------------------------------------------- | ------------------------------------------------------------------------------- |
| `infra/terraform/terraform.tfvars.example`  | Template for all required secrets — must copy and fill before `terraform apply` |
| `infra/terraform/ansible_inventory.tf`      | Auto-generates Ansible inventory with Bastion ProxyCommand                      |
| `infra/ansible/secrets.sh`                  | Sets env vars consumed by Ansible (Discord webhook, Cloudflare Access tokens)   |
| `infra/ansible/group_vars/all.yml`          | Shared variables across all Ansible roles                                       |
| `infra/ansible/roles/monitoring/templates/` | Jinja2 templates for Prometheus, Grafana, Alertmanager configs                  |
| `infra/terraform/modules/cloudflare/`       | Tunnel creation, Load Balancer failover rules                                   |
| `application/k6/.env.testk6`                | Load test parameters (VUs, duration, target URL)                                |

## Secrets & Environment Variables

**terraform.tfvars** (never commit):

- `cf_api_token`, `cf_account_id`, `cf_zone_id`, `cf_tunnel_secret` — Cloudflare credentials (`cf_zone_id` is the Zone ID from the Cloudflare dashboard, distinct from `cf_account_id`)
  - Generate tunnel secret: `openssl rand -base64 32`
- `app_domain`, `monitoring_domain` — Cloudflare-proxied domains for the app and Grafana/Prometheus UI
- `gcp_credentials` — GCP Service Account JSON content. Leave empty for local runs. For GitHub Actions, register as a repository secret in **Settings → Secrets and variables → Actions** of this personal repo (`hjh6709/basic_project_test`)
- `gcp_ssh_public_key` — Full SSH public key string (e.g. `ssh-ed25519 AAAA... ubuntu`) used by Ansible to access GCP nodes
- `key_name` — AWS EC2 Key Pair name (must be pre-created in the AWS console)
- `allowed_ssh_cidr` — Change from `0.0.0.0/0` to your IP (`x.x.x.x/32`) for production

**ansible/secrets.sh**:

- `ALERT_WEBHOOK_URL` — Discord webhook URL
- `CF_CLIENT_ID` / `CF_CLIENT_SECRET` — Cloudflare Access tokens (read from Terraform outputs after `terraform apply`)

**GitHub Actions repository secrets** (Settings → Secrets and variables → Actions in `hjh6709/basic_project_test`):

| Secret | Used by | Description |
|--------|---------|-------------|
| `DISCORD_WEBHOOK` | `pr-discord.yml` | Discord webhook URL for PR open/merge notifications |
| `GCP_CREDENTIALS` | `deploy.yml` (planned) | GCP Service Account JSON for kubectl access |

> `build.yml` and `deploy.yml` are currently placeholder files — populate with actual workflow steps as CI/CD is implemented.

## Cloud SQL (GCP)

| Item | Value |
|------|-------|
| Instance name | `hybrid-primary-db` |
| Database name | `hybrid_app_db` |
| User | `root` |
| Password | `gcp_db_password` from `terraform.tfvars` |
| Access method | Cloud SQL Auth Proxy (IAM auth, public IP with no authorized networks needed) |

Both GCP and AWS K3s clusters connect to this single Cloud SQL instance. `deletion_protection` is disabled for the dev environment.
