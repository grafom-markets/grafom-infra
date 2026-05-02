#!/usr/bin/env bash
# deploy.sh — Sync and deploy shared infrastructure (cloud-agnostic, arc-190)
#
# IMPORTANT: This script is a TRANSITIONAL tool. The target state (arc-190) is:
#   make deploy CLOUD=oracle   →  OpenTofu provisions + Ansible deploys
#
# Until Ansible playbooks are built (bg-020 Phase 2), this script bridges the gap.
# Host/key/user are read from OpenTofu outputs — NOT hardcoded — so switching clouds
# only requires changing terraform.tfvars, running `tofu apply`, then `./deploy.sh`.
#
# Usage:
#   ./ec2/deploy.sh                          # reads host/key from tofu output
#   ./ec2/deploy.sh -k ~/.ssh/other.pem      # override SSH key
#   ./ec2/deploy.sh -h 1.2.3.4              # override host (emergency only)
#
# What it does:
#   1. Reads host, user, ssh key from terraform/outputs (cloud-agnostic)
#   2. Syncs docker-compose.yml, .env, prometheus.yml and all config dirs
#   3. Runs docker compose up -d
#   4. Ensures all per-service PostgreSQL databases exist (idempotent)
#   5. Pre-creates Kafka topics with correct partition counts (idempotent)
#   6. Verifies all 8 containers are running

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOFU_DIR="${SCRIPT_DIR}/../terraform"

# -------------------------------------------------------------------------
# Read host/user/key from OpenTofu outputs (INFRA-001: single switch point)
# Falls back to env vars, then to sensible defaults if tofu is unavailable.
# -------------------------------------------------------------------------
if command -v tofu &>/dev/null && [ -f "${TOFU_DIR}/terraform.tfstate" ]; then
    EC2_HOST=$(cd "$TOFU_DIR" && tofu output -raw instance_ip   2>/dev/null || echo "")
    EC2_USER=$(cd "$TOFU_DIR" && tofu output -raw ssh_user      2>/dev/null || echo "ubuntu")
    SSH_KEY=$(cd  "$TOFU_DIR" && tofu output -raw ssh_key_path  2>/dev/null || echo "")
fi

EC2_HOST="${INFRA_HOST:-${EC2_HOST:-}}"
EC2_USER="${INFRA_USER:-${EC2_USER:-ubuntu}}"
SSH_KEY="${INFRA_SSH_KEY:-${SSH_KEY:-}}"

# Parse flags (override tofu output if explicitly passed)
while getopts "k:h:u:" opt; do
    case $opt in
        k) SSH_KEY="$OPTARG" ;;
        h) EC2_HOST="$OPTARG" ;;
        u) EC2_USER="$OPTARG" ;;
        *) echo "Usage: $0 [-k ssh_key] [-h host] [-u user]"; exit 1 ;;
    esac
done

if [ -z "$EC2_HOST" ] || [ -z "$SSH_KEY" ]; then
    echo "ERROR: Could not determine host or SSH key from tofu output."
    echo "Run 'tofu apply' first, or pass -h <host> -k <key> explicitly."
    exit 1
fi

REMOTE_COMPOSE_DIR="/opt/infra/compose"
REMOTE_CLICKHOUSE_DIR="/opt/infra/clickhouse/init"
REMOTE_CLICKHOUSE_CFG_DIR="/opt/infra/clickhouse/config"
REMOTE_POSTGRES_DIR="/opt/infra/postgres/init"
REMOTE_KAFKA_DIR="/opt/infra/kafka/init"
REMOTE_GRAFANA_DIR="/opt/infra/grafana"
REMOTE_OTEL_DIR="/opt/infra/otel"
REMOTE_CONSOLE_DIR="/opt/infra/redpanda-console"

SSH_CMD="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no ${EC2_USER}@${EC2_HOST}"
SCP_CMD="scp -i ${SSH_KEY} -o StrictHostKeyChecking=no"

echo "=== Grafom Infrastructure Deploy ==="
echo "Target: ${EC2_USER}@${EC2_HOST}"
echo ""

# -------------------------------------------------------------------------
# Step 1: Ensure remote directories exist
# -------------------------------------------------------------------------
echo "[1/6] Ensuring remote directories..."
${SSH_CMD} "sudo mkdir -p ${REMOTE_COMPOSE_DIR} \
            ${REMOTE_CLICKHOUSE_DIR} ${REMOTE_CLICKHOUSE_CFG_DIR} \
            ${REMOTE_POSTGRES_DIR} ${REMOTE_KAFKA_DIR} \
            ${REMOTE_GRAFANA_DIR}/provisioning/datasources \
            ${REMOTE_GRAFANA_DIR}/provisioning/dashboards \
            ${REMOTE_GRAFANA_DIR}/dashboards \
            ${REMOTE_OTEL_DIR} \
            ${REMOTE_CONSOLE_DIR} && \
            mkdir -p /tmp/ch_init /tmp/pg_init"

# -------------------------------------------------------------------------
# Step 2: Sync files to remote host
# -------------------------------------------------------------------------
echo "[2/6] Syncing files..."

# Compose + prometheus
${SCP_CMD} "${SCRIPT_DIR}/docker-compose.yml" "${EC2_USER}@${EC2_HOST}:/tmp/docker-compose.yml"
${SCP_CMD} "${SCRIPT_DIR}/prometheus.yml" "${EC2_USER}@${EC2_HOST}:/tmp/prometheus.yml"

# .env (only if it exists locally — never overwrite blindly)
if [ -f "${SCRIPT_DIR}/.env" ]; then
    ${SCP_CMD} "${SCRIPT_DIR}/.env" "${EC2_USER}@${EC2_HOST}:/tmp/infra.env"
    ${SSH_CMD} "sudo mv /tmp/infra.env ${REMOTE_COMPOSE_DIR}/.env"
    echo "  .env synced"
else
    echo "  .env not found locally — skipping (using existing remote .env)"
fi

# ClickHouse init SQL + Prometheus metrics config
${SCP_CMD} "${SCRIPT_DIR}/clickhouse-init/"*.sql "${EC2_USER}@${EC2_HOST}:/tmp/ch_init/"
${SCP_CMD} "${SCRIPT_DIR}/clickhouse-config/prometheus.xml" "${EC2_USER}@${EC2_HOST}:/tmp/ch_prometheus.xml"
# PostgreSQL init SQL
${SCP_CMD} "${SCRIPT_DIR}/postgres-init/"*.sql "${EC2_USER}@${EC2_HOST}:/tmp/pg_init/"
# Kafka init scripts
${SCP_CMD} "${SCRIPT_DIR}/kafka-init/create-topics.sh" "${EC2_USER}@${EC2_HOST}:/tmp/create-topics.sh"
# Grafana provisioning + dashboards
${SCP_CMD} "${SCRIPT_DIR}/grafana/provisioning/datasources/datasources.yml" "${EC2_USER}@${EC2_HOST}:/tmp/grafana_ds.yml"
${SCP_CMD} "${SCRIPT_DIR}/grafana/provisioning/dashboards/dashboards.yml" "${EC2_USER}@${EC2_HOST}:/tmp/grafana_dash_prov.yml"
${SCP_CMD} "${SCRIPT_DIR}/grafana/dashboards/infra-health.json" "${EC2_USER}@${EC2_HOST}:/tmp/infra-health.json"
# OTEL Collector config
${SCP_CMD} "${SCRIPT_DIR}/otel-config/otel-collector.yml" "${EC2_USER}@${EC2_HOST}:/tmp/otel-collector.yml"
# Redpanda Console config
${SCP_CMD} "${SCRIPT_DIR}/redpanda-console/config.yml" "${EC2_USER}@${EC2_HOST}:/tmp/console-config.yml"

${SSH_CMD} "sudo mv /tmp/docker-compose.yml ${REMOTE_COMPOSE_DIR}/docker-compose.yml && \
            sudo mv /tmp/prometheus.yml ${REMOTE_COMPOSE_DIR}/prometheus.yml && \
            sudo mv /tmp/ch_init/*.sql ${REMOTE_CLICKHOUSE_DIR}/ && \
            sudo mv /tmp/ch_prometheus.xml ${REMOTE_CLICKHOUSE_CFG_DIR}/prometheus.xml && \
            sudo mv /tmp/pg_init/*.sql ${REMOTE_POSTGRES_DIR}/ && \
            sudo mv /tmp/create-topics.sh ${REMOTE_KAFKA_DIR}/create-topics.sh && \
            sudo chmod +x ${REMOTE_KAFKA_DIR}/create-topics.sh && \
            sudo mv /tmp/grafana_ds.yml ${REMOTE_GRAFANA_DIR}/provisioning/datasources/datasources.yml && \
            sudo mv /tmp/grafana_dash_prov.yml ${REMOTE_GRAFANA_DIR}/provisioning/dashboards/dashboards.yml && \
            sudo mv /tmp/infra-health.json ${REMOTE_GRAFANA_DIR}/dashboards/infra-health.json && \
            sudo mv /tmp/otel-collector.yml ${REMOTE_OTEL_DIR}/otel-collector.yml && \
            sudo mv /tmp/console-config.yml ${REMOTE_CONSOLE_DIR}/config.yml"
echo "  All files synced"

# -------------------------------------------------------------------------
# Step 3: docker compose up
# -------------------------------------------------------------------------
echo "[3/6] Starting services..."
${SSH_CMD} "sudo docker compose -f ${REMOTE_COMPOSE_DIR}/docker-compose.yml up -d" 2>&1

# -------------------------------------------------------------------------
# Step 4: Ensure per-service PostgreSQL databases exist
# docker-entrypoint-initdb.d only runs on first init (empty data volume).
# This step handles existing Postgres data volumes by running the script explicitly.
# -------------------------------------------------------------------------
echo ""
echo "[4/6] Creating PostgreSQL databases (idempotent)..."
${SSH_CMD} "sudo docker exec compose-postgres-1 \
    psql -U postgres -f /docker-entrypoint-initdb.d/001_create_databases.sql" 2>&1

# -------------------------------------------------------------------------
# Step 5: Pre-create Kafka topics with correct partition counts
# Without this, Redpanda auto-creates topics with 1 partition.
# -------------------------------------------------------------------------
echo ""
echo "[5/6] Creating Kafka topics (idempotent)..."
${SSH_CMD} "sudo docker cp ${REMOTE_KAFKA_DIR}/create-topics.sh compose-redpanda-1:/tmp/create-topics.sh && \
            sudo docker exec compose-redpanda-1 bash /tmp/create-topics.sh" 2>&1

# -------------------------------------------------------------------------
# Step 6: Verify
# -------------------------------------------------------------------------
echo ""
echo "[6/6] Verifying..."
${SSH_CMD} 'sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
echo ""
${SSH_CMD} 'sudo docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}"'
echo ""
echo "=== Deploy complete === (${EC2_USER}@${EC2_HOST})"
echo "  Grafana:          http://${EC2_HOST}:3000"
echo "  Redpanda Console: http://${EC2_HOST}:8080"
echo "  Prometheus:       http://${EC2_HOST}:9090"
echo "  ClickHouse HTTP:  http://${EC2_HOST}:8123"
echo "  OTLP gRPC:        ${EC2_HOST}:4317"
echo "  Kafka:            ${EC2_HOST}:9092"
echo "  PostgreSQL:       ${EC2_HOST}:5432"
echo "  Redis:            ${EC2_HOST}:6379"
echo ""
echo "Expected containers: postgres, redis, redpanda, redpanda-console,"
echo "  grafom_clickhouse, otel-collector, prometheus, grafana (8 total)"
