#!/usr/bin/env bash
# deploy.sh — Sync and deploy shared infrastructure to EC2
#
# Usage:
#   ./ec2/deploy.sh                          # uses default key + host
#   ./ec2/deploy.sh -k ~/.ssh/other.pem      # custom key
#   ./ec2/deploy.sh -h 1.2.3.4              # custom host
#
# What it does:
#   1. Syncs docker-compose.yml, .env, prometheus.yml to EC2:/opt/infra/compose/
#   2. Syncs clickhouse-init/ and postgres-init/ SQL to EC2
#   3. Runs docker-compose up -d on EC2
#   4. Ensures all per-service PostgreSQL databases exist
#   5. Verifies all containers are running

set -euo pipefail

# Defaults
SSH_KEY="${HOME}/grafom/login.pem"
EC2_HOST="13.51.159.243"
EC2_USER="ubuntu"
REMOTE_COMPOSE_DIR="/opt/infra/compose"
REMOTE_CLICKHOUSE_DIR="/opt/infra/clickhouse/init"
REMOTE_POSTGRES_DIR="/opt/infra/postgres/init"
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
echo "[1/5] Ensuring remote directories..."
${SSH_CMD} "sudo mkdir -p ${REMOTE_COMPOSE_DIR} ${REMOTE_CLICKHOUSE_DIR} ${REMOTE_POSTGRES_DIR} && \
            mkdir -p /tmp/ch_init /tmp/pg_init"

# -------------------------------------------------------------------------
# Step 2: Sync files to EC2
# -------------------------------------------------------------------------
echo "[2/5] Syncing files..."

# Compose + prometheus
${SCP_CMD} "${SCRIPT_DIR}/docker-compose.yml" "${EC2_USER}@${EC2_HOST}:/tmp/docker-compose.yml"
${SCP_CMD} "${SCRIPT_DIR}/prometheus.yml" "${EC2_USER}@${EC2_HOST}:/tmp/prometheus.yml"

# .env (only if it exists locally — never overwrite blindly)
if [ -f "${SCRIPT_DIR}/.env" ]; then
    ${SCP_CMD} "${SCRIPT_DIR}/.env" "${EC2_USER}@${EC2_HOST}:/tmp/infra.env"
    ${SSH_CMD} "sudo mv /tmp/infra.env ${REMOTE_COMPOSE_DIR}/.env"
    echo "  .env synced"
else
    echo "  .env not found locally — skipping (using existing on EC2)"
fi

# ClickHouse init SQL
${SCP_CMD} "${SCRIPT_DIR}/clickhouse-init/"*.sql "${EC2_USER}@${EC2_HOST}:/tmp/ch_init/"
# PostgreSQL init SQL
${SCP_CMD} "${SCRIPT_DIR}/postgres-init/"*.sql "${EC2_USER}@${EC2_HOST}:/tmp/pg_init/"
${SSH_CMD} "sudo mv /tmp/docker-compose.yml ${REMOTE_COMPOSE_DIR}/docker-compose.yml && \
            sudo mv /tmp/prometheus.yml ${REMOTE_COMPOSE_DIR}/prometheus.yml && \
            sudo mv /tmp/ch_init/*.sql ${REMOTE_CLICKHOUSE_DIR}/ && \
            sudo mv /tmp/pg_init/*.sql ${REMOTE_POSTGRES_DIR}/"
echo "  All files synced"

# -------------------------------------------------------------------------
# Step 3: docker-compose up
# -------------------------------------------------------------------------
echo "[3/5] Starting services..."
${SSH_CMD} "sudo docker-compose -f ${REMOTE_COMPOSE_DIR}/docker-compose.yml up -d" 2>&1

# -------------------------------------------------------------------------
# Step 4: Ensure per-service PostgreSQL databases exist
# docker-entrypoint-initdb.d only runs on first init (empty data volume).
# This step handles existing Postgres data volumes by running the script explicitly.
# -------------------------------------------------------------------------
echo ""
echo "[4/5] Creating PostgreSQL databases (idempotent)..."
${SSH_CMD} "sudo docker exec compose_postgres_1 \
    psql -U postgres -f /docker-entrypoint-initdb.d/001_create_databases.sql" 2>&1

# -------------------------------------------------------------------------
# Step 5: Verify
# -------------------------------------------------------------------------
echo ""
echo "[5/5] Verifying..."
${SSH_CMD} 'sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
echo ""
${SSH_CMD} 'sudo docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}"'
echo ""
echo "=== Deploy complete ==="
echo "  Compose:    http://${EC2_HOST}:3000 (Grafana)"
echo "  ClickHouse: http://${EC2_HOST}:8123 (HTTP)"
echo "  Kafka:      ${EC2_HOST}:9092"
echo "  PostgreSQL:  ${EC2_HOST}:5432"
echo "  Redis:       ${EC2_HOST}:6379"
