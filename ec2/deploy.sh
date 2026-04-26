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
#   2. Syncs clickhouse-init/ SQL to EC2:/opt/infra/clickhouse/init/
#   3. Runs docker-compose up -d on EC2
#   4. Verifies all containers are running

set -euo pipefail

# Defaults
SSH_KEY="${HOME}/grafom/login.pem"
EC2_HOST="13.51.159.243"
EC2_USER="ubuntu"
REMOTE_COMPOSE_DIR="/opt/infra/compose"
REMOTE_CLICKHOUSE_DIR="/opt/infra/clickhouse/init"
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
echo "[1/4] Ensuring remote directories..."
${SSH_CMD} "sudo mkdir -p ${REMOTE_COMPOSE_DIR} ${REMOTE_CLICKHOUSE_DIR}"

# -------------------------------------------------------------------------
# Step 2: Sync files to EC2
# -------------------------------------------------------------------------
echo "[2/4] Syncing files..."

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
${SCP_CMD} "${SCRIPT_DIR}/clickhouse-init/"*.sql "${EC2_USER}@${EC2_HOST}:/tmp/"
${SSH_CMD} "sudo mv /tmp/docker-compose.yml ${REMOTE_COMPOSE_DIR}/docker-compose.yml && \
            sudo mv /tmp/prometheus.yml ${REMOTE_COMPOSE_DIR}/prometheus.yml && \
            sudo mv /tmp/*.sql ${REMOTE_CLICKHOUSE_DIR}/"
echo "  All files synced"

# -------------------------------------------------------------------------
# Step 3: docker-compose up
# -------------------------------------------------------------------------
echo "[3/4] Starting services..."
${SSH_CMD} "sudo docker-compose -f ${REMOTE_COMPOSE_DIR}/docker-compose.yml up -d" 2>&1

# -------------------------------------------------------------------------
# Step 4: Verify
# -------------------------------------------------------------------------
echo ""
echo "[4/4] Verifying..."
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
