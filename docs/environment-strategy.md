# Environment Strategy — Configuration Across Environments

How configuration varies across environments, and the pattern services must follow for
environment-specific behavior. All configuration follows
[std-170](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/standards/std-170-configuration-management.md)
(12-factor, env vars, startup validation, no hardcoded URLs).

---

## Table of Contents

1. [Environment Definitions](#1-environment-definitions)
2. [What Changes Between Environments](#2-what-changes-between-environments)
3. [What Stays the Same](#3-what-stays-the-same)
4. [Configuration Pattern](#4-configuration-pattern)
5. [Secret Management Evolution](#5-secret-management-evolution)
6. [Database per Environment](#6-database-per-environment)

---

## 1. Environment Definitions

| Environment | Infrastructure | Region | Purpose | Who Uses It |
|-------------|---------------|--------|---------|-------------|
| **dev/local** | Docker Compose on Mac | — | Per-developer local development | Individual developer |
| **ec2-test** | Docker Compose on shared EC2 | eu-north-1 (Stockholm) | Integration testing, cross-service validation | All developers |
| **staging** | EKS + managed services | ap-south-1 (Mumbai) | Pre-production validation, mirrors prod topology | QA, all developers |
| **production** | EKS + managed services | ap-south-1 (Mumbai) | Live trading, real broker connections | End users |

### dev/local

Each service repo contains a `docker-compose.dev.yml` that spins up its own PostgreSQL,
Redis, and any other dependencies locally. Services run on the developer's Mac (or in a
local container). No shared state — each developer has an isolated environment.

### ec2-test

The shared EC2 instance at `13.51.159.243` (t3.micro, 1 GB RAM). All 6 infrastructure
services run as Docker containers managed by `grafom-infra/ec2/docker-compose.yml`.
Services connect from developers' Macs to the EC2 backends via public IP. This is the
current active environment — see [architecture.md](./architecture.md) Phase 0.

### staging (future)

EKS cluster in ap-south-1 (Mumbai) that mirrors the production topology at reduced scale.
Managed services (RDS, ElastiCache, MSK) at smaller instance sizes. Uses the same
Kubernetes manifests as production with staging-specific ConfigMaps and Secrets. Deployed
via ArgoCD from a `staging` branch or namespace override.

### production (future)

Full-scale EKS cluster in ap-south-1 per
[arc-060](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-060-cloud-infrastructure.md).
Multi-AZ deployment, Graviton ARM instances, Istio service mesh, real broker API
connections (Zerodha, Dhan, Angel One).

---

## 2. What Changes Between Environments

### Infrastructure connection matrix

| Config | dev/local | ec2-test | staging | production |
|--------|-----------|----------|---------|------------|
| PostgreSQL host | `localhost` | `13.51.159.243` | RDS endpoint (`.rds.amazonaws.com`) | RDS endpoint (`.rds.amazonaws.com`) |
| PostgreSQL port | `5432` | `5432` | `5432` | `5432` |
| PostgreSQL user | `postgres` | `postgres` | `grafom_svc` | `grafom_svc` |
| PostgreSQL password | `postgres` (local) | `.env` value | AWS Secrets Manager | AWS Secrets Manager (rotated) |
| PostgreSQL SSL | disabled | disabled | `sslmode=require` | `sslmode=verify-full` |
| Redis host | `localhost` | `13.51.159.243` | ElastiCache endpoint | ElastiCache endpoint |
| Redis auth | none | none | AUTH token | AUTH token + in-transit TLS |
| Kafka brokers | `localhost:9092` | `13.51.159.243:9092` | MSK bootstrap servers | MSK bootstrap servers |
| Kafka auth | none (Redpanda) | none (Redpanda) | IAM auth (MSK) | IAM auth (MSK) |
| ClickHouse host | `localhost` | `13.51.159.243` | EKS internal service | EKS internal service |
| ClickHouse user | `grafom` | `grafom` | `grafom_svc` | `grafom_svc` |
| ClickHouse password | `grafom` | `grafom` | AWS Secrets Manager | AWS Secrets Manager |
| JWT signing keys | local `keys/` files | local `keys/` files | AWS Secrets Manager | AWS Secrets Manager |
| OTEL endpoint | none (or local) | `13.51.159.243:4317` | Grafana Cloud (Mumbai) | Grafana Cloud (Mumbai) |
| Log level | `debug` | `debug` | `info` | `info` |
| Log format | `text` (console) | `text` | `json` | `json` |
| SSL/TLS (service) | disabled | disabled | required (Istio mTLS) | required (Istio mTLS) |
| gRPC port | per service | per service | `8080` (K8s convention) | `8080` (K8s convention) |
| HTTP port | per service | per service | `8081` (K8s convention) | `8081` (K8s convention) |

### Behavioral differences

| Behavior | dev/local | ec2-test | staging | production |
|----------|-----------|----------|---------|------------|
| Broker API connections | mock/sandbox | mock/sandbox | sandbox (paper trade) | live (real orders) |
| Email/SMS notifications | console log | console log | test recipients only | real recipients |
| Rate limiting | disabled | disabled | enabled (relaxed) | enabled (strict) |
| Data retention (ClickHouse TTL) | 7 days | 30 days | 90 days | per arc-180 policy |
| Backups | none | manual (upgrade-runbook) | automated daily | automated + PITR |
| Health probes | optional | Docker healthcheck | K8s liveness/readiness | K8s liveness/readiness |

---

## 3. What Stays the Same

These are **invariants** — they must be identical across all environments. If any of these
differ between environments, it is a bug.

| Invariant | Why |
|-----------|-----|
| Database schema names and migrations | A migration that works in dev must work in prod. Schema drift between environments causes deployment failures. |
| Kafka topic names and partition keys | Consumers depend on topic naming (`<domain>.<entity>.<event>.<version>` per [std-070](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/standards/std-070-kafka-guidelines.md)). Partition key logic determines data locality. |
| Kafka partition counts | Changing partition counts between environments changes consumer behavior and ordering guarantees. |
| ClickHouse table schemas and materialized views | The 20 tables/views in `ec2/clickhouse-init/` are the canonical DDL. Staging and production must use the same schemas. |
| gRPC proto contracts | Service-to-service contracts are defined by `.proto` files. These are version-controlled and environment-independent. |
| Domain logic and business rules | Signal scoring, risk calculations, position tracking — all business logic is environment-agnostic. |
| Service port assignments | Each service's gRPC/HTTP port pair is fixed (defined in `service.yaml`). |
| API versioning and routing | URL paths, gRPC method names, and API versions do not change per environment. |
| Error codes and response formats | Clients (web, mobile) must not branch on environment. |

---

## 4. Configuration Pattern

### Per std-170: all config via environment variables

Every service follows [CFG-001](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/standards/std-170-configuration-management.md):
all runtime configuration is injected via environment variables. No YAML config files, no
JSON config files, no `.properties` files at runtime.

### File layout in each service repo

```
grafom-<service>/
├── .env.example        # Template — committed, safe defaults for local dev
├── .env.ec2            # EC2 testing config — committed, points at 13.51.159.243
├── .env                # Local overrides — gitignored, never committed
├── service.yaml        # Config schema — documents all env vars, defaults, types (CFG-004)
└── deploy/
    └── k8s/
        ├── configmap.yaml      # Non-secret config (staging/prod)
        └── secret.yaml         # Placeholder — real values from External Secrets Operator
```

### How config is provided per environment

| Environment | Config source | Secret source |
|-------------|--------------|---------------|
| dev/local | `.env` file (copied from `.env.example`) | `.env` file (dev-only passwords) |
| ec2-test | `.env.ec2` file (committed) | `.env.ec2` file (dev-only passwords) |
| staging | K8s ConfigMap + K8s Secret | AWS Secrets Manager → External Secrets Operator → K8s Secret |
| production | K8s ConfigMap + K8s Secret | AWS Secrets Manager → External Secrets Operator → K8s Secret |

### .env.example template (local development)

```bash
# grafom-<service> — local development configuration
# Copy to .env: cp .env.example .env

# Database
DATABASE_URL=postgres://postgres:postgres@localhost:5432/grafom_<context>?sslmode=disable

# Redis
REDIS_URL=redis://localhost:6379

# Kafka
KAFKA_BROKERS=localhost:9092

# ClickHouse (if this service reads from ClickHouse)
CLICKHOUSE_HOST=localhost
CLICKHOUSE_PORT=9000
CLICKHOUSE_USER=grafom
CLICKHOUSE_PASSWORD=grafom
CLICKHOUSE_DATABASE=grafom

# Service ports
GRPC_PORT=<service-specific>
HTTP_PORT=<service-specific>

# Observability
LOG_LEVEL=debug
LOG_FORMAT=text
OTEL_EXPORTER_OTLP_ENDPOINT=

# JWT (identity service only, or services that validate tokens)
JWT_PRIVATE_KEY_PATH=./keys/private.pem
JWT_PUBLIC_KEY_PATH=./keys/public.pem
```

### .env.ec2 template (shared EC2 testing)

```bash
# grafom-<service> — EC2 shared instance configuration
# Source: source .env.ec2

EC2_HOST=13.51.159.243

# Database
DATABASE_URL=postgres://postgres:${POSTGRES_PASSWORD}@${EC2_HOST}:5432/grafom_<context>?sslmode=disable

# Redis
REDIS_URL=redis://${EC2_HOST}:6379

# Kafka
KAFKA_BROKERS=${EC2_HOST}:9092

# ClickHouse
CLICKHOUSE_HOST=${EC2_HOST}
CLICKHOUSE_PORT=9000
CLICKHOUSE_USER=grafom
CLICKHOUSE_PASSWORD=grafom
CLICKHOUSE_DATABASE=grafom

# Service ports (same as local)
GRPC_PORT=<service-specific>
HTTP_PORT=<service-specific>

# Observability
LOG_LEVEL=debug
LOG_FORMAT=text
OTEL_EXPORTER_OTLP_ENDPOINT=http://${EC2_HOST}:4317
```

### Kubernetes ConfigMap (staging/production)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafom-<service>-config
  namespace: grafom-<domain>
data:
  GRPC_PORT: "8080"
  HTTP_PORT: "8081"
  LOG_LEVEL: "info"
  LOG_FORMAT: "json"
  KAFKA_BROKERS: "<msk-bootstrap-servers>"
  CLICKHOUSE_HOST: "clickhouse.grafom-data.svc.cluster.local"
  CLICKHOUSE_PORT: "9000"
  CLICKHOUSE_DATABASE: "grafom"
  OTEL_EXPORTER_OTLP_ENDPOINT: "https://otlp-gateway-prod-ap-south-1.grafana.net/otlp"
```

Secrets (DATABASE_URL, REDIS_URL, CLICKHOUSE_PASSWORD, JWT keys) are never in ConfigMaps.
They come from AWS Secrets Manager via External Secrets Operator (see Section 5).

### Startup validation (CFG-003)

Every service must validate all required config at startup and fail fast:

```go
// Go example
type Config struct {
    DatabaseURL  string `envconfig:"DATABASE_URL" required:"true"`
    RedisURL     string `envconfig:"REDIS_URL" required:"true"`
    KafkaBrokers string `envconfig:"KAFKA_BROKERS" required:"true"`
    GRPCPort     int    `envconfig:"GRPC_PORT" required:"true"`
    LogLevel     string `envconfig:"LOG_LEVEL" default:"info"`
}
```

```python
# Python example
class Config(BaseSettings):
    database_url: str
    redis_url: str
    kafka_brokers: str
    grpc_port: int
    log_level: str = "info"
```

If a required variable is missing, the service logs the error and exits with code 1.
This surfaces misconfiguration immediately rather than failing at first use.

---

## 5. Secret Management Evolution

| Concern | Phase 0 (ec2-test) | Phase 2 (staging) | Phase 3 (production) |
|---------|-------------------|-------------------|---------------------|
| Storage | `.env` files on disk | AWS Secrets Manager | AWS Secrets Manager |
| Injection | `source .env.ec2` | External Secrets Operator → K8s Secret → env var | External Secrets Operator → K8s Secret → env var |
| Rotation | Manual (change .env, redeploy) | Quarterly via Secrets Manager rotation lambda | Quarterly (or on-demand) via rotation lambda |
| Encryption at rest | None (plaintext .env) | KMS-encrypted in Secrets Manager | KMS-encrypted (CMK in ap-south-1) |
| Encryption in transit | None (no TLS) | TLS 1.3 (Istio mTLS + RDS SSL) | TLS 1.3 (Istio mTLS + RDS SSL) |
| Access control | Anyone with SSH key | IAM role per service (IRSA) | IAM role per service (IRSA) |
| Audit trail | None | CloudTrail logs secret access | CloudTrail logs + alerting |

### Phase 0 — .env files (current)

Passwords are dev-only throwaway values. `.env` is gitignored. `.env.ec2` is committed
because it contains no real secrets — only dev passwords that are documented in
[CLAUDE.md](../CLAUDE.md) and [run-070](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/runbooks/run-070-ec2-infrastructure-setup.md).

```
.env.example   → committed, CHANGE_ME placeholders
.env           → gitignored, real dev passwords
.env.ec2       → committed, dev-only passwords (acceptable per SEC-001)
```

### Phase 2 — AWS Secrets Manager + External Secrets Operator

Each secret is stored in Secrets Manager under a path convention:

```
grafom/<environment>/<service>/<secret-name>
```

Examples:
```
grafom/staging/identity/database-url
grafom/staging/identity/jwt-private-key
grafom/production/execution/database-url
grafom/production/execution/broker-api-key
```

External Secrets Operator (ESO) runs in the EKS cluster and syncs secrets into
Kubernetes Secret objects:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: grafom-identity-secrets
  namespace: grafom-platform
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: grafom-identity-secrets
  data:
    - secretKey: DATABASE_URL
      remoteRef:
        key: grafom/production/identity/database-url
    - secretKey: JWT_PRIVATE_KEY
      remoteRef:
        key: grafom/production/identity/jwt-private-key
```

### Phase 3 — Terraform-managed secrets

Secrets Manager secret resources are defined in Terraform. Rotation lambdas are deployed
via Terraform. IAM policies granting IRSA roles access to specific secrets are codified
in `terraform/modules/secrets/`.

---

## 6. Database per Environment

### PostgreSQL

| Environment | Infrastructure | Database strategy | Connection pattern |
|-------------|---------------|-------------------|-------------------|
| dev/local | Docker container per service | Each service spins up its own `postgres:15` in `docker-compose.dev.yml` | `localhost:5432/grafom_<context>` |
| ec2-test | Shared Docker container | Single PostgreSQL instance, 13 separate databases (`grafom_identity`, `grafom_execution`, etc.) | `13.51.159.243:5432/grafom_<context>` |
| staging | Amazon RDS (db.t4g.medium) | Shared RDS instance, 13 separate databases | RDS endpoint `:5432/grafom_<context>` |
| production | Amazon RDS (db.r6g.large) | Shared RDS with potential split for high-traffic services | RDS endpoint(s) `:5432/grafom_<context>` |

**Production database split** (if needed):

If a service's query load justifies a dedicated RDS instance, it gets its own:

| RDS Instance | Databases | Justification |
|-------------|-----------|---------------|
| `grafom-primary` | All 13 databases (default) | Shared instance, cost-efficient |
| `grafom-execution` (optional) | `grafom_execution`, `grafom_risk` | High write throughput from order fills and risk snapshots |
| `grafom-market` (optional) | `grafom_market_ingestion` | High write throughput from tick data ingestion |

The split is transparent to services — only the `DATABASE_URL` env var changes. No code
changes required. This is the benefit of CFG-005 (no hardcoded connection strings).

### ClickHouse

| Environment | Infrastructure | Schema |
|-------------|---------------|--------|
| dev/local | Docker container (optional — not all services need ClickHouse) | Same 20 tables/views from `ec2/clickhouse-init/` |
| ec2-test | Shared Docker container | `ec2/clickhouse-init/` DDL (canonical) |
| staging | Self-managed on EKS or ClickHouse Cloud | Same DDL, applied via init Job or migration tool |
| production | Self-managed on EKS or ClickHouse Cloud | Same DDL |

ClickHouse ingestion is always via the Kafka table engine (AB-006), never direct writes.
The Kafka broker endpoint changes between environments, but the materialized view
pipeline stays identical.

### Redis

| Environment | Infrastructure | Auth |
|-------------|---------------|------|
| dev/local | Docker container per service | none |
| ec2-test | Shared Docker container | none |
| staging | Amazon ElastiCache | AUTH token + TLS |
| production | Amazon ElastiCache (Multi-AZ, cluster mode) | AUTH token + TLS |

Redis is a cache (Tier 3 per arc-050). Data loss on restart is acceptable. Services must
handle cache misses gracefully — a cold Redis must not prevent service startup.

### Kafka / Redpanda

| Environment | Infrastructure | Auth | Topics |
|-------------|---------------|------|--------|
| dev/local | Redpanda in `docker-compose.dev.yml` | none | Auto-created on first produce |
| ec2-test | Shared Redpanda container | none | Pre-created by `kafka-init/create-topics.sh` (25 topics) |
| staging | Amazon MSK | IAM auth | Created via Terraform or rpk with IAM |
| production | Amazon MSK (Multi-AZ, 3 brokers) | IAM auth | Created via Terraform |

Topic names, partition counts, and partition key logic are environment-invariant (Section 3).

---

## Related

- [architecture.md](./architecture.md) — Infrastructure evolution phases
- [upgrade-runbook.md](./upgrade-runbook.md) — Maintenance procedures for EC2
- [std-170](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/standards/std-170-configuration-management.md) — Configuration management standard
- [std-160](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/standards/std-160-deployment-release.md) — Deployment and release standard
- [arc-060](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-060-cloud-infrastructure.md) — Cloud infrastructure (EKS production target)
