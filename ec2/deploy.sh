#!/usr/bin/env bash
# deploy.sh — Sync and deploy shared infrastructure to Oracle Cloud A1
#
# Usage:
#   ./ec2/deploy.sh                          # uses default key + host
#   ./ec2/deploy.sh -k ~/.ssh/other.pem      # custom key
#   ./ec2/deploy.sh -h 1.2.3.4              # custom host
#
# What it does:
#   1. Syncs docker-compose.yml, .env, prometheus.yml to Oracle A1:/opt/infra/compose/
#   2. Syncs clickhouse-init/, clickhouse-config/, postgres-init/, kafka-init/, grafana/,
#      otel-config/, redpanda-console/ to Oracle A1
#   3. Runs docker compose up -d on Oracle A1
#   4. Ensures all per-service PostgreSQL databases exist
#   5. Pre-creates Kafka topics with correct partition counts
#   6. Verifies all 8 containers are running
#
# Target: Oracle Cloud A1 (arc-190) — 80.225.199.245, 24 GB RAM, Always Free

set -euo pipefail

# Defaults
SSH_KEY="${HOME}/grafom/oracle-api-key.pem"
EC2_HOST="80.225.199.245"
EC2_USER="ubuntu"
REMOTE_COMPOSE_DIR="/opt/infra/compose"
REMOTE_CLICKHOUSE_DIR="/opt/infra/clickhouse/init"
REMOTE_CLICKHOUSE_CFG_DIR="/opt/infra/clickhouse/config"
REMOTE_POSTGRES_DIR="/opt/infra/postgres/init"
REMOTE_KAFKA_DIR="/opt/infra/kafka/init"
REMOTE_GRAFANA_DIR="/opt/infra/grafana"
REMOTE_OTEL_DIR="/opt/infra/otel"
REMOTE_CONSOLE_DIR="/opt/infra/redpanda-console"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Parse flags
while getopts "k:h:" opt; do
    case $opt in
        k) SSH_KEY="$OPTARG" ;;
        h) EC2_HOST="$OPTARG" ;;
        *) echo "Usage: $0 [-k ssh_key] [-h ec2_host]"; exit 1 ;;
    esac
done

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
# Step 2: Sync files to Oracle A1
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
    echo "  .env not found locally — skipping (using existing on Oracle A1)"
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
echo "=== Deploy complete === (Oracle Cloud A1 — 80.225.199.245)"
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
