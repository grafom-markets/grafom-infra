# grafom-infra — AI Context File

## What This Repo Is

Infrastructure configuration for the Grafom platform. Contains Docker Compose definitions,
database init scripts, monitoring configs, and deployment scripts. Not a service — no
application code.

## Structure

| Directory | Purpose |
|-----------|---------|
| `ec2/` | Shared EC2 dev/test infrastructure (current phase) |
| `ec2/clickhouse-init/` | ClickHouse DDL — 4 SQL files, 20 tables/views |
| `ec2/postgres-init/` | PostgreSQL init — creates 13 per-service databases |
| `ec2/kafka-init/` | Kafka topic pre-creation with partition counts (rpk) |
| `ec2/grafana/` | Grafana provisioning (data sources, dashboards) |
| `ec2/security-group.md` | Security group rules — canonical reference |
| `docs/` | Architecture and operations documentation |
| `docs/architecture.md` | Infrastructure evolution (Phase 0 EC2 → Phase 2 EKS → Phase 3 Terraform) |
| `docs/upgrade-runbook.md` | EC2 resize, backups, version upgrades, emergency recovery |
| `docs/environment-strategy.md` | Config per environment, secret management, database strategy |
| `k8s/` | Future: EKS Kubernetes manifests |
| `terraform/` | OpenTofu IaC — cloud-agnostic (AWS/GCP/Azure/Oracle) |

## Infrastructure Management

Cloud resources managed by OpenTofu in `terraform/`.
Switch clouds: `make apply CLOUD=<aws|gcp|azure|oracle>`

| Role | Cloud | Region | Instance | RAM | Free Tier | IP | SSH |
|------|-------|--------|----------|-----|-----------|-----|-----|
| **Primary** | Oracle | ap-mumbai-1 | VM.Standard.A1.Flex (4 OCPU, ARM64) | 24 GB | Always-free | 80.225.199.245 | `ssh grafom-oracle` |
| Secondary | AWS | eu-north-1 | t3.micro | 1 GB + 2 GB swap | 12 months | 13.63.244.213 | `ssh -i ~/.ssh/grafom_infra ubuntu@13.63.244.213` |
| Tertiary | GCP | us-central1 | e2-micro (monitoring only) | 1 GB + 2 GB swap | Always-free | 34.27.120.191 | `ssh -i ~/.ssh/grafom_infra ubuntu@34.27.120.191` |

**OpenTofu workspaces:** Each cloud has its own workspace (`tofu workspace select aws|oracle|gcp`).
- `aws` workspace: EC2 instance + SG + EIP + key pair
- `oracle` workspace: VCN + subnet + instance + reserved IP
- `gcp` workspace: static IP + firewall + e2-micro instance

## Services Running

| Service | Container Name | Port(s) |
|---------|---------------|---------|
| PostgreSQL 15 | compose-postgres-1 | 5432 |
| Redis 7 | compose-redis-1 | 6379 |
| Redpanda | compose-redpanda-1 | 9092, 9644 |
| ClickHouse 24.8 | grafom_clickhouse | 8123, 9000 |
| Prometheus | compose-prometheus-1 | 9090 |
| Grafana 9.5 | compose-grafana-1 | 3000 |

## Credentials (dev only)

| Service | User | Password |
|---------|------|----------|
| PostgreSQL | postgres | (see ec2/.env) |
| ClickHouse | grafom | grafom |
| Grafana | admin | (see ec2/.env) |
| Redis | (none) | (none) |

## Deploy

```bash
# Oracle (primary)
./ec2/deploy.sh -k ~/.ssh/grafom_infra -h 80.225.199.245

# AWS (secondary — full stack)
./ec2/deploy.sh -k ~/.ssh/grafom_infra -h 13.63.244.213

# GCP (tertiary — Prometheus + Grafana only)
# Full deploy.sh then stop heavy containers
```

## Key Constraints

- **SEC-001:** Never commit real credentials. Use `.env.example` as template, `.env` is gitignored.
- **AB-006:** ClickHouse ingests via Kafka table engine, not direct writes from services.
- ClickHouse TTL on DateTime64 columns requires `toDateTime()` cast (ClickHouse 24.8 limitation).

## Architecture References

- [arc-050](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-050-data-architecture.md) — Three-tier data architecture
- [arc-180](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-180-clickhouse-time-series.md) — ClickHouse adoption
- [run-070](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/runbooks/run-070-ec2-infrastructure-setup.md) — EC2 setup runbook
