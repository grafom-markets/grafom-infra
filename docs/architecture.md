# Infrastructure Evolution — grafom-infra

## 1. Overview

`grafom-infra` manages all infrastructure configuration across environments. The repo is
structured around deployment phases — each top-level directory corresponds to an
infrastructure target:

| Directory | Phase | Status |
|-----------|-------|--------|
| `ec2/` | Phase 0 — Docker Compose on a single EC2 | **Active** |
| `k8s/` | Phase 2 — EKS Kubernetes manifests | Planned |
| `terraform/` | Phase 3 — Infrastructure as Code | Planned |

Every phase builds on the previous one. The Docker Compose definitions in `ec2/` are the
living spec for what must exist in every higher environment. Nothing moves to EKS or
Terraform that was not first proven on EC2.

### Guiding principles

1. **One repo, all environments.** Infrastructure config never lives inside service repos.
2. **Prove on EC2 first.** New services, schemas, and topics are validated on the shared
   instance before being promoted.
3. **Managed services over self-hosted.** In production, prefer RDS over self-managed
   PostgreSQL, MSK over self-managed Kafka, etc.
4. **GitOps.** Every infrastructure change is a commit. ArgoCD (Phase 2+) reconciles the
   cluster from this repo.

---

## 2. Phase 0 — EC2 Docker Compose (current)

**Status:** Active
**Instance:** t3.micro (1 GB RAM), eu-north-1 (Stockholm)
**IP:** 13.51.159.243

A single EC2 instance running all shared infrastructure as Docker containers. This is the
development and integration-testing environment for all 13 Grafom services.

### Services

| Service | Image | Port(s) | Architecture Ref |
|---------|-------|---------|------------------|
| PostgreSQL 15 | `postgres:15` | 5432 | [arc-050](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-050-data-architecture.md) Tier 1 |
| Redis 7 | `redis:7` | 6379 | [arc-050](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-050-data-architecture.md) Tier 3 |
| Redpanda | `redpandadata/redpanda:latest` | 9092, 9644 | [arc-020](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-020-event-driven-kafka.md) |
| ClickHouse 24.8 | `clickhouse/clickhouse-server:24.8-alpine` | 8123, 9000 | [arc-180](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-180-clickhouse-time-series.md) |
| Prometheus | `prom/prometheus:latest` | 9090 | [arc-090](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-090-observability-stack.md) |
| Grafana 9.5 | `grafana/grafana:9.5.0` | 3000 | [arc-090](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-090-observability-stack.md) |

### Deployment model

```
Local machine                           EC2 (13.51.159.243)
  ec2/                  scp/ssh         /opt/infra/
  ├── docker-compose.yml  ──────────►   ├── compose/
  ├── .env                              │   ├── docker-compose.yml
  ├── prometheus.yml                    │   ├── .env
  ├── clickhouse-init/                  │   └── prometheus.yml
  ├── postgres-init/                    ├── clickhouse/init/
  ├── kafka-init/                       ├── postgres/init/
  └── grafana/                          ├── kafka/init/
                                        └── grafana/
```

`deploy.sh` handles the full cycle: sync files, `docker-compose up -d`, create PostgreSQL
databases, pre-create Kafka topics, verify containers.

### What this phase proves

- All 13 service databases can coexist on one PostgreSQL instance
- ClickHouse DDL (20 tables/views) initializes correctly
- Kafka topics are created with correct partition counts and naming
- Grafana connects to all data sources via provisioning
- Prometheus scrapes all services that expose metrics

### Limitations

- Single point of failure (one instance, no replication)
- No autoscaling, no load balancing
- All security group rules are 0.0.0.0/0 (acceptable for dev only)
- 1 GB RAM limits concurrent service testing
- No TLS, no service mesh, no network policies

---

## 3. Phase 1 — EC2 Multi-Instance (optional)

**Status:** Not started
**Trigger:** When the t3.micro becomes a bottleneck for integration testing.

An intermediate step before Kubernetes. Separate stateful services (PostgreSQL, ClickHouse,
Redis) from stateless ones (Prometheus, Grafana) across 2-3 EC2 instances.

### What changes

| Concern | Phase 0 | Phase 1 |
|---------|---------|---------|
| Compute | 1x t3.micro | 2-3x t3.small/medium |
| Data services | All on one host | Dedicated data instance |
| Networking | Docker bridge | Private VPC subnets |
| Security groups | One SG, all ports | Per-service SGs |

### When to skip this phase

Skip Phase 1 and go directly to EKS if:
- The team is already comfortable with Kubernetes
- The t3.micro is sufficient until EKS is ready
- There is no need for multi-instance integration testing

---

## 4. Phase 2 — EKS (Kubernetes)

**Status:** Planned
**Region:** ap-south-1 (Mumbai) — co-located with NSE/BSE market data feeds
**Reference:** [arc-060](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-060-cloud-infrastructure.md)

Production deployment on Amazon EKS. Self-hosted Docker containers are replaced by AWS
managed services where available.

### Service mapping

| Phase 0 (Docker) | Phase 2 (EKS) | Notes |
|-------------------|---------------|-------|
| `postgres:15` | Amazon RDS PostgreSQL 16 | Multi-AZ, automated backups |
| `redis:7` | Amazon ElastiCache Redis | Cluster mode, encryption at rest |
| `redpandadata/redpanda` | Amazon MSK (Kafka) | Managed Kafka, no operational overhead |
| `clickhouse-server` | ClickHouse Cloud or self-managed on EKS | Evaluate cost vs. operational burden |
| `prom/prometheus` | Amazon Managed Prometheus (AMP) | Or self-managed with Thanos |
| `grafana/grafana` | Amazon Managed Grafana (AMG) | SSO integration via AWS IAM Identity Center |

### Kubernetes architecture

```
EKS Cluster (ap-south-1)
├── Namespace: grafom-data          # Stateful: CH if self-managed
├── Namespace: grafom-market        # Market data services (ctx-020, ctx-030)
├── Namespace: grafom-signal        # Signal generation (ctx-040, ctx-050)
├── Namespace: grafom-execution     # Order execution (ctx-060, ctx-070)
├── Namespace: grafom-platform      # Identity, notification, billing (ctx-080–130)
├── Namespace: grafom-observability # Prometheus, Grafana, alerting
└── Namespace: argocd               # GitOps controller
```

### 13 services on EKS

All 13 bounded-context services ([arc-040](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-040-deployment-extraction.md))
deploy as Kubernetes Deployments with HPA (Horizontal Pod Autoscaler). Each service gets:

- A Deployment + Service + HPA
- ConfigMap for environment config
- Secret for credentials (from AWS Secrets Manager via External Secrets Operator)
- NetworkPolicy restricting ingress to its namespace

### Key infrastructure components

| Component | Tool | Purpose |
|-----------|------|---------|
| Cluster autoscaling | Karpenter | Right-sizes nodes, supports Spot instances |
| GitOps | ArgoCD | Reconciles `k8s/` manifests to the cluster |
| Ingress | AWS ALB Ingress Controller | Routes external traffic to services |
| Secrets | External Secrets Operator | Syncs AWS Secrets Manager into K8s Secrets |
| Observability | AMP + AMG | Managed Prometheus + Grafana |
| TLS | AWS ACM | Certificates for ALB |

### Estimated cost

~55,000-70,000 INR/month for the base EKS cluster with managed services, before
data transfer and storage costs scale with usage.

---

## 5. Phase 3 — Terraform + GitOps

**Status:** Planned (after EKS is operational)
**Reference:** [arc-060 §IaC](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-060-cloud-infrastructure.md)

All AWS resources (VPC, subnets, EKS cluster, RDS, ElastiCache, MSK, IAM roles) are
defined in Terraform. The `terraform/` directory becomes the source of truth for cloud
infrastructure, while `k8s/` remains the source of truth for workload manifests.

### Workflow

```
Developer ──► PR to grafom-infra ──► CI runs terraform plan ──► Review ──► Merge
                                                                              │
                                                              terraform apply ◄┘
                                                                              │
                                                              ArgoCD sync ◄───┘
```

### What Terraform manages

- VPC, subnets, route tables, NAT gateways
- EKS cluster, node groups, Karpenter provisioners
- RDS instances, ElastiCache clusters, MSK clusters
- IAM roles and policies (IRSA for pod-level permissions)
- Security groups (replacing the manual `security-group.md`)
- S3 buckets, CloudWatch log groups

### What Terraform does NOT manage

- Kubernetes workloads (Deployments, Services, HPA) — managed by ArgoCD from `k8s/`
- Application-level configuration — managed by ConfigMaps in `k8s/`
- Database schemas and migrations — managed by each service's own repo

---

## 6. Directory Mapping

How each directory in this repo maps to the infrastructure evolution:

| Path | Phase | Purpose | Migrates To |
|------|-------|---------|-------------|
| `ec2/docker-compose.yml` | 0 | Service definitions | `k8s/` Deployments + managed services |
| `ec2/.env` | 0 | Credentials | AWS Secrets Manager + External Secrets |
| `ec2/prometheus.yml` | 0 | Scrape config | `k8s/grafom-observability/` ConfigMap |
| `ec2/clickhouse-init/` | 0 | ClickHouse DDL | `k8s/grafom-data/` init Job or ClickHouse Cloud migrations |
| `ec2/postgres-init/` | 0 | Database creation | RDS — databases created via Terraform or migration tool |
| `ec2/kafka-init/` | 0 | Topic pre-creation | MSK — topics created via Terraform `aws_msk_topic` or rpk |
| `ec2/grafana/` | 0 | Dashboards + datasources | AMG provisioning or `k8s/grafom-observability/` |
| `ec2/security-group.md` | 0 | SG documentation | `terraform/modules/networking/` SG resources |
| `ec2/deploy.sh` | 0 | Manual deploy script | Replaced by ArgoCD + Terraform CI/CD |
| `k8s/` | 2 | Kubernetes manifests | ArgoCD source of truth |
| `terraform/` | 3 | IaC definitions | Terraform Cloud or CI-driven `terraform apply` |

---

## 7. Migration Checklist

Use this checklist when transitioning between phases.

### Phase 0 → Phase 2 (EC2 → EKS)

- [ ] Provision VPC and subnets in ap-south-1 (Mumbai)
- [ ] Create EKS cluster with managed node group
- [ ] Install ArgoCD, Karpenter, External Secrets Operator, ALB Ingress Controller
- [ ] Provision RDS PostgreSQL 16 (Multi-AZ) — migrate 13 databases
- [ ] Provision ElastiCache Redis cluster — verify cache key compatibility
- [ ] Provision MSK cluster — recreate 25 topics with same partition counts
- [ ] Evaluate ClickHouse Cloud vs. self-managed ClickHouse on EKS
- [ ] Migrate ClickHouse DDL (20 tables/views) to target environment
- [ ] Create Kubernetes manifests for all 13 services in `k8s/`
- [ ] Configure HPA for each service based on [arc-040](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-040-deployment-extraction.md) CPU/memory targets
- [ ] Set up NetworkPolicies per namespace
- [ ] Migrate Prometheus scrape configs to AMP or self-managed Prometheus on EKS
- [ ] Migrate Grafana dashboards to AMG or self-managed Grafana on EKS
- [ ] Configure DNS (Route 53) for service endpoints
- [ ] Set up TLS via ACM + ALB
- [ ] Smoke test: all 13 services connect to managed backends
- [ ] Update `CLAUDE.md` with new connection details

### Phase 2 → Phase 3 (manual AWS → Terraform)

- [ ] Import existing AWS resources into Terraform state
- [ ] Define VPC, EKS, RDS, ElastiCache, MSK as Terraform modules
- [ ] Set up Terraform state backend (S3 + DynamoDB locking)
- [ ] Configure CI pipeline for `terraform plan` on PR, `terraform apply` on merge
- [ ] Replace `security-group.md` manual tracking with Terraform SG resources
- [ ] Define IAM roles and IRSA policies in Terraform
- [ ] Tag all resources with `project:grafom`, `environment:production`, `managed-by:terraform`
- [ ] Verify `terraform plan` shows no drift from running infrastructure

---

## Related

- [arc-040](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-040-deployment-extraction.md) — Service deployment and extraction strategy
- [arc-060](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-060-cloud-infrastructure.md) — Cloud infrastructure architecture (EKS, managed services)
- [road-010](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/roadmap/road-010-delivery-roadmap.md) — Delivery roadmap and phasing
- [run-070](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/runbooks/run-070-ec2-infrastructure-setup.md) — EC2 setup runbook
- [ec2/security-group.md](../ec2/security-group.md) — Security group canonical reference
