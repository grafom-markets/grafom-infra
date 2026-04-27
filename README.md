# grafom-infra

Infrastructure configuration for the Grafom platform. Version-controlled source of truth for all deployment artifacts.

## Structure

```
ec2/                              Current phase: shared EC2 dev/test instance
  docker-compose.yml              Service definitions (Postgres, Redis, Redpanda, ClickHouse, Prometheus, Grafana)
  .env.example                    Credential template
  deploy.sh                       One-command deploy to EC2
  prometheus.yml                  Prometheus scrape targets
  security-group.md               AWS Security Group rules — canonical reference
  clickhouse-init/                ClickHouse DDL — 4 SQL files, 20 tables/views (auto-runs on first start)
  postgres-init/                  PostgreSQL init — creates 13 per-service databases
  kafka-init/                     Kafka topic pre-creation — 25 topics with partition counts (rpk)
  grafana/                        Grafana provisioning
    provisioning/datasources/     Data source config (Prometheus, ClickHouse, PostgreSQL)
    provisioning/dashboards/      Dashboard file provider
    dashboards/                   Dashboard JSON (infra-health)

docs/                             Architecture and operations documentation
  architecture.md                 Infrastructure evolution (Phase 0 EC2 → EKS → Terraform)
  upgrade-runbook.md              EC2 resize, backups, version upgrades, emergency recovery
  environment-strategy.md         Config per environment, secret management, database strategy

k8s/                              Future: EKS Kubernetes manifests
terraform/                        Future: Infrastructure as Code
```

## Quick Start

```bash
# Deploy to EC2
cp ec2/.env.example ec2/.env    # fill in real credentials
./ec2/deploy.sh

# Custom SSH key or host
./ec2/deploy.sh -k ~/.ssh/my-key.pem -h 1.2.3.4
```

## What deploy.sh does

1. Syncs docker-compose.yml, .env, prometheus.yml to EC2
2. Syncs clickhouse-init/, postgres-init/, kafka-init/, grafana/ to EC2
3. Runs `docker-compose up -d`
4. Creates all 13 PostgreSQL databases (idempotent)
5. Pre-creates all 25 Kafka topics (idempotent)
6. Verifies all containers are running

## EC2 Instance

| Property | Value |
|----------|-------|
| IP | 13.51.159.243 |
| Type | t3.micro (1 GB RAM) |
| Region | eu-north-1 (Stockholm) |
| Security Group | sg-02ab16897e5744c5b |
| SSH | `ssh -i ~/grafom/login.pem ubuntu@13.51.159.243` |

## Services

| Service | Port(s) | Architecture Ref |
|---------|---------|-----------------|
| PostgreSQL 15 | 5432 | arc-050 Tier 1 |
| Redis 7 | 6379 | arc-050 Tier 3 |
| Redpanda | 9092, 9644 | arc-020 |
| ClickHouse 24.8 | 8123, 9000 | arc-180 |
| Prometheus | 9090 | arc-090 |
| Grafana 9.5 | 3000 | arc-090 |

## Documentation

| Document | Purpose |
|----------|---------|
| [Infrastructure Evolution](docs/architecture.md) | How infra progresses from EC2 → EKS → Terraform |
| [Upgrade Runbook](docs/upgrade-runbook.md) | Step-by-step procedures for maintenance tasks |
| [Environment Strategy](docs/environment-strategy.md) | Configuration across dev/ec2/staging/production |
| [Security Group Reference](ec2/security-group.md) | Inbound rules, risk assessment, AWS CLI commands |

## Related

- [arc-050 Data Architecture](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-050-data-architecture.md)
- [arc-180 ClickHouse](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-180-clickhouse-time-series.md)
- [run-070 EC2 Setup Runbook](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/runbooks/run-070-ec2-infrastructure-setup.md)
