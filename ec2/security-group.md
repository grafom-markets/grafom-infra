# AWS Security Group — Canonical Reference

**Security Group ID:** `sg-02ab16897e5744c5b` (launch-wizard-1)
**Region:** eu-north-1 (Stockholm)
**Instance:** 13.51.159.243 (t3.micro)

This file is the single source of truth for inbound rules on the shared EC2 dev/test
instance. All changes to the security group MUST be reflected here.

**AWS Console path:**
EC2 → Network & Security → Security Groups → `sg-02ab16897e5744c5b` → Edit inbound rules

---

## 1. Active Inbound Rules

As of 2026-04-27. All rules are TCP. Outbound is unrestricted (default).

| Port | Protocol | Source | Service | Docker Service | Architecture Ref |
|------|----------|--------|---------|----------------|------------------|
| 22 | TCP | 0.0.0.0/0 | SSH | — | — |
| 3000 | TCP | 0.0.0.0/0 | Grafana | `grafana` | [arc-090](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-090-observability-stack.md) |
| 5432 | TCP | 0.0.0.0/0 | PostgreSQL | `postgres` | [arc-050](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-050-data-architecture.md) Tier 1 |
| 6379 | TCP | 0.0.0.0/0 | Redis | `redis` | [arc-050](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-050-data-architecture.md) Tier 3 |
| 8123 | TCP | 0.0.0.0/0 | ClickHouse HTTP | `clickhouse` | [arc-180](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-180-clickhouse-time-series.md) |
| 9000 | TCP | 0.0.0.0/0 | ClickHouse Native TCP | `clickhouse` | [arc-180](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-180-clickhouse-time-series.md) |
| 9090 | TCP | 0.0.0.0/0 | Prometheus | `prometheus` | [arc-090](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-090-observability-stack.md) |
| 9092 | TCP | 0.0.0.0/0 | Redpanda / Kafka | `redpanda` | [arc-020](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-020-event-driven-kafka.md) |
| 9644 | TCP | 0.0.0.0/0 | Redpanda Admin API | `redpanda` | [arc-020](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/arch/arc-020-event-driven-kafka.md) |

**Total: 9 inbound rules.**

---

## 2. Removed Rules

Ports removed from the security group after decommissioning services that are not
in the ratified architecture. See [run-070 §2](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/runbooks/run-070-ec2-infrastructure-setup.md) for decommission steps.

| Port | Service | Date Removed | Reason |
|------|---------|-------------|--------|
| 27017 | MongoDB | 2026-04-27 | Not in arc-050. Rejected — no relational integrity for financial data. No bounded context uses it. |
| 8086 | InfluxDB | 2026-04-27 | Superseded by ClickHouse (arc-180). Proprietary query language, no clustering in OSS v2. |
| 8080 | Weaviate | 2026-04-27 | No bounded context uses vector search. Container was already crashed/stopped. |

---

## 3. Security Hardening Notes

> **Current state: all ports open to `0.0.0.0/0` (the entire internet).**
> This is acceptable for short-lived testing but is a security risk if left indefinitely.

### Risk assessment

| Port | Service | Risk if exposed | Auth | Priority to restrict |
|------|---------|----------------|------|---------------------|
| 5432 | PostgreSQL | **HIGH** — full DB read/write | Password only (see `.env`) | Restrict immediately |
| 6379 | Redis | **HIGH** — no authentication, full read/write/flush | None | Restrict immediately |
| 9000 | ClickHouse Native | **MEDIUM** — read/write to analytics DB | Password (`grafom/grafom`) | Restrict |
| 8123 | ClickHouse HTTP | **MEDIUM** — same as above via HTTP | Password (`grafom/grafom`) | Restrict |
| 22 | SSH | **MEDIUM** — key-based only (no password) | PEM key file | Restrict |
| 9092 | Redpanda/Kafka | **MEDIUM** — can produce/consume events | None | Restrict |
| 9644 | Redpanda Admin | **MEDIUM** — cluster management API | None | Restrict |
| 9090 | Prometheus | **LOW** — read-only metrics | None | Optional |
| 3000 | Grafana | **LOW** — has its own login (admin/password) | Password (see `.env`) | Optional |

### Production recommendations

1. **Minimum action:** Restrict PostgreSQL (5432) and Redis (6379) to your IP immediately.
   These have weak/no passwords and allow full data access.
2. **Recommended:** Restrict all ports to developer IPs using `/32` CIDR masks.
3. **Grafana exception:** Port 3000 can stay `0.0.0.0/0` if remote access from varying
   networks is needed — Grafana has its own authentication.
4. **Dynamic IP workaround:** If your ISP assigns dynamic IPs, use a `/24` CIDR
   (e.g., `49.36.100.0/24`) to cover the range.

### Find your public IP

```bash
curl -s ifconfig.me
```

---

## 4. AWS CLI Commands

All commands require `aws` CLI configured with appropriate credentials and the
`--region eu-north-1` flag (or set via `AWS_DEFAULT_REGION`).

### Variables

```bash
SG_ID="sg-02ab16897e5744c5b"
MY_IP="$(curl -s ifconfig.me)/32"
echo "Your IP: $MY_IP"
```

### Add a rule

```bash
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 5432 \
    --cidr "$MY_IP" \
    --region eu-north-1
```

### Remove a rule

```bash
aws ec2 revoke-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 27017 \
    --cidr "0.0.0.0/0" \
    --region eu-north-1
```

### Tighten all ports to your IP

> **Warning:** This will lock you out of SSH if `$MY_IP` is wrong.
> Double-check the value before running. Keep the AWS Console open as a fallback.

```bash
SG_ID="sg-02ab16897e5744c5b"
MY_IP="$(curl -s ifconfig.me)/32"
REGION="eu-north-1"

echo "Restricting all ports to: $MY_IP"
echo "Press Ctrl+C within 5 seconds to abort..."
sleep 5

for PORT in 22 3000 5432 6379 8123 9000 9090 9092 9644; do
    echo "  Port $PORT: revoking 0.0.0.0/0..."
    aws ec2 revoke-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port "$PORT" \
        --cidr "0.0.0.0/0" \
        --region "$REGION" 2>/dev/null || true

    echo "  Port $PORT: adding $MY_IP..."
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port "$PORT" \
        --cidr "$MY_IP" \
        --region "$REGION" 2>/dev/null || true
done

echo "Done. Verify with:"
echo "  aws ec2 describe-security-groups --group-ids $SG_ID --region $REGION --query 'SecurityGroups[0].IpPermissions' --output table"
```

### Reopen all ports (emergency / reset)

```bash
SG_ID="sg-02ab16897e5744c5b"
REGION="eu-north-1"

for PORT in 22 3000 5432 6379 8123 9000 9090 9092 9644; do
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port "$PORT" \
        --cidr "0.0.0.0/0" \
        --region "$REGION" 2>/dev/null || true
done
```

### Verify current rules

```bash
aws ec2 describe-security-groups \
    --group-ids "sg-02ab16897e5744c5b" \
    --region eu-north-1 \
    --query 'SecurityGroups[0].IpPermissions[*].{Port:FromPort,Source:IpRanges[0].CidrIp}' \
    --output table
```

---

## 5. Change Log

| Date | Change | Ports Affected | Reason |
|------|--------|---------------|--------|
| 2026-04-27 | Removed MongoDB rule | 27017 | Service decommissioned — not in architecture (run-070 §2) |
| 2026-04-27 | Removed InfluxDB rule | 8086 | Superseded by ClickHouse (arc-180) |
| 2026-04-27 | Removed Weaviate rule | 8080 | No bounded context uses vector search |
| 2026-04-27 | Added ClickHouse HTTP | 8123 | ClickHouse deployment (arc-180) |
| 2026-04-27 | Added ClickHouse Native TCP | 9000 | ClickHouse deployment (arc-180) |
| 2026-04-27 | Documented all rules | all | Created canonical reference (this file) |

---

## Related

- [run-070 §5](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/runbooks/run-070-ec2-infrastructure-setup.md) — EC2 setup runbook (SG configuration steps)
- [CLAUDE.md](../CLAUDE.md) — Infra repo context (instance details, credentials)
- [docker-compose.yml](./docker-compose.yml) — Service definitions and port mappings
