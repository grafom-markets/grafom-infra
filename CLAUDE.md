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
| `k8s/` | Future: EKS Kubernetes manifests |
| `terraform/` | Future: Infrastructure as Code |

## EC2 Instance

- **IP:** 13.51.159.243
- **Type:** t3.micro (1 GB RAM)
- **Region:** eu-north-1 (Stockholm)
- **Security Group:** sg-02ab16897e5744c5b
- **SSH:** `ssh -i ~/grafom/login.pem ubuntu@13.51.159.243`
- **Docker commands require `sudo`**

## Services Running

| Service | Container Name | Port(s) |
|---------|---------------|---------|
| PostgreSQL 15 | compose_postgres_1 | 5432 |
| Redis 7 | compose_redis_1 | 6379 |
| Redpanda | compose_redpanda_1 | 9092, 9644 |
| ClickHouse 24.8 | grafom_clickhouse | 8123, 9000 |
| Prometheus | compose_prometheus_1 | 9090 |
| Grafana 9.5 | compose_grafana_1 | 3000 |

## Credentials (dev only)

| Service | User | Password |
|---------|------|----------|
| PostgreSQL | postgres | (see ec2/.env) |
| ClickHouse | grafom | grafom |
| Grafana | admin | (see ec2/.env) |
| Redis | (none) | (none) |

## Deploy

```bash
./ec2/deploy.sh
```

## Key Constraints

- **SEC-001:** Never commit real credentials. Use `.env.example` as template, `.env` is gitignored.
- **AB-006:** ClickHouse ingests via Kafka table engine, not direct writes from services.
- ClickHouse TTL on DateTime64 columns requires `toDateTime()` cast (ClickHouse 24.8 limitation).

## Architecture References

- [arc-050](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-050-data-architecture.md) — Three-tier data architecture
- [arc-180](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-180-clickhouse-time-series.md) — ClickHouse adoption
- [run-070](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/runbooks/run-070-ec2-infrastructure-setup.md) — EC2 setup runbook
