# grafom-infra

Infrastructure configuration for the Grafom platform. Version-controlled source of truth for all deployment artifacts.

## Structure

```
ec2/                    Current phase: shared EC2 dev/test instance
  docker-compose.yml    Service definitions (Postgres, Redis, Redpanda, ClickHouse, Prometheus, Grafana)
  .env.example          Credential template
  clickhouse-init/      ClickHouse DDL (auto-runs on first start)
  prometheus.yml        Prometheus scrape targets
  deploy.sh             One-command deploy to EC2

k8s/                    Future: EKS Kubernetes manifests
terraform/              Future: Infrastructure as Code
```

## Quick Start

```bash
# Deploy to EC2
cp ec2/.env.example ec2/.env    # fill in real credentials
./ec2/deploy.sh

# Custom SSH key or host
./ec2/deploy.sh -k ~/.ssh/my-key.pem -h 1.2.3.4
```

## EC2 Instance

| Property | Value |
|----------|-------|
| IP | 13.51.159.243 |
| Type | t3.micro (1 GB RAM) |
| Region | eu-north-1 (Stockholm) |
| Security Group | sg-02ab16897e5744c5b |

## Services

| Service | Port(s) | Architecture Ref |
|---------|---------|-----------------|
| PostgreSQL 15 | 5432 | arc-050 Tier 1 |
| Redis 7 | 6379 | arc-050 Tier 3 |
| Redpanda | 9092, 9644 | arc-020 |
| ClickHouse 24.8 | 8123, 9000 | arc-180 |
| Prometheus | 9090 | arc-090 |
| Grafana 9.5 | 3000 | arc-090 |

## Related

- [arc-050 Data Architecture](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-050-data-architecture.md)
- [arc-180 ClickHouse](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-180-clickhouse-time-series.md)
- [run-070 EC2 Setup Runbook](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/runbooks/run-070-ec2-infrastructure-setup.md)
