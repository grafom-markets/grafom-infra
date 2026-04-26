#!/usr/bin/env bash
# create-topics.sh — Pre-create all Kafka topics with correct partition counts
#
# Runs inside the Redpanda container via rpk. Idempotent — safe to run repeatedly.
# Without this, Redpanda auto-creates topics with 1 partition, hiding partitioning bugs.
#
# Topic naming follows std-070: <domain>.<entity>.<event>.<version>
# Partition counts reflect throughput and ordering requirements per arc-020.
#
# Usage (on EC2):
#   docker exec compose_redpanda_1 bash /tmp/create-topics.sh
#
# References: std-070, arc-020, arc-180, svc-010

set -euo pipefail

BROKERS="localhost:9092"
RF=1  # replication factor 1 for single-node dev

create_topic() {
    local name="$1"
    local partitions="$2"
    rpk topic create "$name" -p "$partitions" -r "$RF" --brokers "$BROKERS" 2>/dev/null || true
}

echo "=== Creating Kafka topics ==="

# -------------------------------------------------------------------------
# Market Intelligence domain (ctx-020)
# Produced by: market-ingestion-service, market-intelligence-service
# Consumed by: ClickHouse (arc-180), strategy-engine, signal-scoring, dashboard-bff
# -------------------------------------------------------------------------
echo "[market] Creating market domain topics..."
create_topic "market.instrument.tick.v1"    6   # high-volume tick stream, partition by symbol hash
create_topic "market.ohlcv.bar.v1"          3   # aggregated OHLCV bars
create_topic "market.options.chain.v1"      3   # options chain snapshots
create_topic "market.regime.changed.v1"     1   # regime classification events

# -------------------------------------------------------------------------
# Strategy & Scoring domain (ctx-030, ctx-040)
# Produced by: strategy-engine-service, signal-scoring-service
# Consumed by: signal-scoring, execution, notification, dashboard-bff, compliance
# -------------------------------------------------------------------------
echo "[strategy/signal] Creating strategy & scoring topics..."
create_topic "strategy.signal.generated.v1" 3   # strategy trigger signals
create_topic "signal.score.updated.v1"      3   # composite score updates (ClickHouse: score_history)

# -------------------------------------------------------------------------
# Execution domain (ctx-050)
# Produced by: execution-service
# Consumed by: risk, reporting, notification, dashboard-bff, compliance, ClickHouse
# -------------------------------------------------------------------------
echo "[execution] Creating execution domain topics..."
create_topic "execution.order.placed.v1"    3   # new orders submitted
create_topic "execution.order.filled.v1"    3   # order fills (ClickHouse: fills table)
create_topic "execution.order.cancelled.v1" 1   # low volume, ordering matters
create_topic "execution.order.rejected.v1"  1   # low volume

# -------------------------------------------------------------------------
# Risk domain (ctx-060)
# Produced by: risk-service
# Consumed by: execution, notification, dashboard-bff, compliance, ClickHouse
# -------------------------------------------------------------------------
echo "[risk] Creating risk domain topics..."
create_topic "risk.breach.detected.v1"        1   # ordering critical — single partition
create_topic "risk.position.updated.v1"       3   # position risk snapshots (ClickHouse: risk_snapshots)
create_topic "risk.kill-switch.activated.v1"   1   # global kill switch — single partition

# -------------------------------------------------------------------------
# Identity domain (ctx-080)
# Produced by: identity-service
# Consumed by: billing, notification, compliance
# -------------------------------------------------------------------------
echo "[identity] Creating identity domain topics..."
create_topic "user.registered.v1"           1
create_topic "user.profile.updated.v1"      1
create_topic "user.deleted.v1"              1
create_topic "user.session.created.v1"      1
create_topic "user.session.revoked.v1"      1
create_topic "user.2fa.status.changed.v1"   1
create_topic "user.deletion.requested.v1"   1

# -------------------------------------------------------------------------
# Billing domain (ctx-100)
# Produced by: billing-service
# Consumed by: notification, compliance, dashboard-bff
# -------------------------------------------------------------------------
echo "[billing] Creating billing domain topics..."
create_topic "billing.subscription.created.v1"   1
create_topic "billing.subscription.cancelled.v1" 1
create_topic "billing.payment.processed.v1"      1

# -------------------------------------------------------------------------
# Notification domain (ctx-110)
# Produced by: notification-service
# Consumed by: dashboard-bff, compliance
# -------------------------------------------------------------------------
echo "[notification] Creating notification topic..."
create_topic "notification.send.requested.v1" 3

# -------------------------------------------------------------------------
# Reporting domain (ctx-120)
# Produced by: reporting-service
# Consumed by: notification
# -------------------------------------------------------------------------
echo "[reporting] Creating reporting topic..."
create_topic "reporting.pnl.computed.v1" 3

# -------------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------------
echo ""
echo "=== Topic creation complete ==="
echo ""
rpk topic list --brokers "$BROKERS"
