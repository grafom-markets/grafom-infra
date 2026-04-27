# Upgrade Runbook — EC2 Infrastructure Maintenance

Step-by-step procedures for common infrastructure maintenance tasks that involve risk of
data loss or downtime. All procedures assume the current Phase 0 EC2 setup
(see [architecture.md](./architecture.md)).

**Instance:** t3.micro, eu-north-1 (Stockholm), 13.51.159.243
**SSH:** `ssh -i ~/grafom/login.pem ubuntu@13.51.159.243`
**Compose directory:** `/opt/infra/compose/`
**Docker commands require `sudo`** on EC2.

---

## Table of Contents

1. [Resize EC2 Instance](#1-resize-ec2-instance-t3micro--t3smallmedium)
2. [Assign Elastic IP](#2-assign-elastic-ip-preserve-ip-across-restarts)
3. [Backup Docker Volumes](#3-backup-docker-volumes-before-destructive-changes)
4. [Upgrade PostgreSQL Version](#4-upgrade-postgresql-version-15--16)
5. [Upgrade ClickHouse Version](#5-upgrade-clickhouse-version-248--newer)
6. [Upgrade Redpanda Version](#6-upgrade-redpanda-version)
7. [Emergency: Recover from Corrupted Volume](#7-emergency-recover-from-corrupted-volume)

---

## 1. Resize EC2 Instance (t3.micro → t3.small/medium)

**Downtime:** 2-5 minutes (instance stop/start cycle).
**Risk:** Public IP changes unless an Elastic IP is attached. All service repos that
hardcode the IP in `.env.ec2` will need updating.

### RAM budget reference (from [run-070 §9](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/runbooks/run-070-ec2-infrastructure-setup.md))

| Instance | RAM | Monthly Cost (eu-north-1) | Recommendation |
|----------|-----|--------------------------|---------------|
| t3.micro | 1 GB | ~$8 | Current — fits 1 service testing remotely |
| t3.small | 2 GB | ~$16 | Comfortable for identity + 1-2 more services |
| t3.medium | 4 GB | ~$32 | Full cross-service testing with multiple services |

### Option A — Resize without Elastic IP (IP may change)

#### Step 1.A.1 — Record current state

```bash
# On your Mac — note the current IP
echo "Current IP: 13.51.159.243"

# SSH into EC2 and verify all services
ssh -i ~/grafom/login.pem ubuntu@13.51.159.243
sudo docker ps --format "table {{.Names}}\t{{.Status}}"
sudo docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}"
free -m
exit
```

#### Step 1.A.2 — Stop the instance

**AWS Console:**
EC2 → Instances → select instance → Instance state → Stop instance

**AWS CLI:**

```bash
INSTANCE_ID="<your-instance-id>"   # find in AWS Console → Instances
REGION="eu-north-1"

aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$REGION"
aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID" --region "$REGION"
echo "Instance stopped."
```

#### Step 1.A.3 — Change instance type

**AWS Console:**
EC2 → Instances → select stopped instance → Actions → Instance settings → Change instance type → select t3.small or t3.medium → Apply

**AWS CLI:**

```bash
aws ec2 modify-instance-attribute \
    --instance-id "$INSTANCE_ID" \
    --instance-type '{"Value": "t3.small"}' \
    --region "$REGION"
```

#### Step 1.A.4 — Start the instance

```bash
aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$REGION"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

# Get the new public IP
NEW_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)
echo "New IP: $NEW_IP"
```

#### Step 1.A.5 — If IP changed, update everywhere

If `$NEW_IP` differs from `13.51.159.243`:

1. **Security group** — no change needed (SG is attached to instance, not IP)
2. **grafom-infra repo:**
   - `CLAUDE.md` — update IP
   - `ec2/deploy.sh` — update `EC2_HOST`
   - `ec2/security-group.md` — update instance IP in header
   - `docs/architecture.md` — update IP references
3. **All service repos** — update `.env.ec2` files with new IP:
   ```
   DB_HOST=<new-ip>
   REDIS_HOST=<new-ip>
   KAFKA_BROKERS=<new-ip>:9092
   ```
4. **grafom-architecture-hub:**
   - `run-070` — update IP references

#### Step 1.A.6 — Verify services restarted

All containers have `restart: unless-stopped`, so they auto-start with the instance.

```bash
ssh -i ~/grafom/login.pem ubuntu@$NEW_IP

# All 6 containers should be running
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Expected:
#   compose_postgres_1     Up ...   0.0.0.0:5432->5432/tcp
#   compose_redis_1        Up ...   0.0.0.0:6379->6379/tcp
#   compose_redpanda_1     Up ...   0.0.0.0:9092->9092/tcp, 0.0.0.0:9644->9644/tcp
#   grafom_clickhouse      Up ...   0.0.0.0:8123->8123/tcp, 0.0.0.0:9000->9000/tcp
#   compose_prometheus_1   Up ...   0.0.0.0:9090->9090/tcp
#   compose_grafana_1      Up ...   0.0.0.0:3000->3000/tcp

# Verify RAM improvement
free -m
sudo docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}"
```

### Option B — Assign Elastic IP first, then resize (IP preserved)

Complete [Section 2](#2-assign-elastic-ip-preserve-ip-across-restarts) first, then follow
Option A steps 1.A.2 through 1.A.4. Skip step 1.A.5 entirely — the Elastic IP
stays attached through stop/start cycles.

---

## 2. Assign Elastic IP (preserve IP across restarts)

**Downtime:** None (allocation is instant, association takes seconds).
**Cost:** ~$3.65/month when attached to a running instance. ~$3.65/month when NOT
attached (AWS charges for idle Elastic IPs). Free only while attached to a running instance
in the free tier.

> **Recommendation:** Assign an Elastic IP before any resize or maintenance that requires
> instance stop/start. This avoids cascading `.env.ec2` updates across all service repos.

### Step 2.1 — Allocate an Elastic IP

**AWS Console:**
EC2 → Network & Security → Elastic IPs → Allocate Elastic IP address → Allocate

**AWS CLI:**

```bash
REGION="eu-north-1"

ALLOC=$(aws ec2 allocate-address --domain vpc --region "$REGION")
EIP_ALLOC_ID=$(echo "$ALLOC" | jq -r '.AllocationId')
EIP_ADDRESS=$(echo "$ALLOC" | jq -r '.PublicIp')
echo "Allocated: $EIP_ADDRESS (ID: $EIP_ALLOC_ID)"
```

### Step 2.2 — Associate with the instance

**AWS Console:**
Elastic IPs → select the new EIP → Actions → Associate Elastic IP address → select
instance → Associate

**AWS CLI:**

```bash
INSTANCE_ID="<your-instance-id>"

aws ec2 associate-address \
    --allocation-id "$EIP_ALLOC_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION"
```

> **Warning:** This replaces the current public IP immediately. If the new EIP differs
> from 13.51.159.243, update all references as described in Step 1.A.5.

### Step 2.3 — Verify SSH access

```bash
ssh -i ~/grafom/login.pem ubuntu@$EIP_ADDRESS
sudo docker ps --format "table {{.Names}}\t{{.Status}}"
exit
```

### Step 2.4 — Update references (if EIP differs from current IP)

If the allocated EIP is different from `13.51.159.243`, follow Step 1.A.5 to update
all repos. After this one-time update, the IP is permanent — future stop/start cycles
will not change it.

### Release an Elastic IP (if no longer needed)

```bash
# First disassociate
ASSOC_ID=$(aws ec2 describe-addresses \
    --allocation-ids "$EIP_ALLOC_ID" \
    --region "$REGION" \
    --query 'Addresses[0].AssociationId' \
    --output text)
aws ec2 disassociate-address --association-id "$ASSOC_ID" --region "$REGION"

# Then release
aws ec2 release-address --allocation-id "$EIP_ALLOC_ID" --region "$REGION"
```

---

## 3. Backup Docker Volumes (before destructive changes)

**Downtime:** Depends on data size. PostgreSQL pg_dumpall runs online (no downtime).
ClickHouse backup requires brief read pause. Redis RDB copy is instant.

> **Rule:** Always run this section before any version upgrade, volume removal, or
> instance resize.

### Step 3.1 — List current volumes

```bash
ssh -i ~/grafom/login.pem ubuntu@13.51.159.243

sudo docker volume ls --format "table {{.Name}}\t{{.Driver}}"
# Expected:
#   compose_postgres_data
#   compose_redis_data
#   compose_redpanda_data
#   compose_clickhouse_data
#   compose_clickhouse_logs
#   compose_prometheus_data
#   compose_grafana_data
```

### Step 3.2 — Backup PostgreSQL (all 13 databases)

```bash
# On EC2 — dumps all databases, roles, and schemas to a single SQL file
sudo docker exec compose_postgres_1 \
    pg_dumpall -U postgres > /tmp/pg_backup_$(date +%Y%m%d_%H%M%S).sql

# Verify the backup contains all 13 grafom_* databases
grep "CREATE DATABASE" /tmp/pg_backup_*.sql

# Copy to your Mac
exit
scp -i ~/grafom/login.pem ubuntu@13.51.159.243:/tmp/pg_backup_*.sql ~/grafom/backups/
```

**Per-database backup** (if you only need one):

```bash
sudo docker exec compose_postgres_1 \
    pg_dump -U postgres -d grafom_identity > /tmp/pg_identity_$(date +%Y%m%d).sql
```

### Step 3.3 — Backup ClickHouse

```bash
# On EC2 — list tables to back up
sudo docker exec grafom_clickhouse \
    clickhouse-client --query "SELECT database, name, engine FROM system.tables WHERE database = 'grafom'" --format PrettyCompact

# Export each table to native format (most efficient for restore)
BACKUP_DIR="/tmp/ch_backup_$(date +%Y%m%d_%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"

for TABLE in $(sudo docker exec grafom_clickhouse \
    clickhouse-client --query "SELECT name FROM system.tables WHERE database = 'grafom' AND engine NOT LIKE '%View%'" --format TabSeparated); do
    echo "Backing up grafom.$TABLE..."
    sudo docker exec grafom_clickhouse \
        clickhouse-client --query "SELECT * FROM grafom.$TABLE FORMAT Native" > "$BACKUP_DIR/$TABLE.native"
done

# Export DDL (table schemas) for all tables and views
sudo docker exec grafom_clickhouse \
    clickhouse-client --query "SELECT name, create_table_query FROM system.tables WHERE database = 'grafom'" --format TabSeparated > "$BACKUP_DIR/ddl.tsv"

echo "Backup complete: $BACKUP_DIR"
ls -lh "$BACKUP_DIR"
```

**Copy to Mac:**

```bash
exit
scp -i ~/grafom/login.pem -r ubuntu@13.51.159.243:/tmp/ch_backup_* ~/grafom/backups/
```

### Step 3.4 — Backup Redis

Redis with `appendonly yes` writes to an AOF file, plus periodic RDB snapshots.

```bash
# On EC2 — trigger a synchronous RDB save
sudo docker exec compose_redis_1 redis-cli BGSAVE

# Wait for save to complete (usually <1 second for small datasets)
sleep 2
sudo docker exec compose_redis_1 redis-cli LASTSAVE

# Copy the RDB file from the volume
REDIS_VOL=$(sudo docker volume inspect compose_redis_data --format '{{.Mountpoint}}')
sudo cp "$REDIS_VOL/dump.rdb" /tmp/redis_backup_$(date +%Y%m%d_%H%M%S).rdb

# Copy to Mac
exit
scp -i ~/grafom/login.pem ubuntu@13.51.159.243:/tmp/redis_backup_*.rdb ~/grafom/backups/
```

### Step 3.5 — Backup Grafana (dashboards + datasources)

Grafana dashboards are provisioned from files (no need to back up the volume for
dashboards), but any manually created dashboards live in the SQLite DB inside the volume.

```bash
# On EC2
GRAFANA_VOL=$(sudo docker volume inspect compose_grafana_data --format '{{.Mountpoint}}')
sudo cp "$GRAFANA_VOL/grafana.db" /tmp/grafana_backup_$(date +%Y%m%d_%H%M%S).db
```

### Restore procedures

#### Restore PostgreSQL

```bash
# On EC2 — assumes a fresh or empty PostgreSQL container is running
cat /tmp/pg_backup_YYYYMMDD_HHMMSS.sql | \
    sudo docker exec -i compose_postgres_1 psql -U postgres

# Verify
sudo docker exec compose_postgres_1 \
    psql -U postgres -c "SELECT datname FROM pg_database WHERE datname LIKE 'grafom_%' ORDER BY datname"
```

#### Restore ClickHouse

```bash
# On EC2 — assumes grafom database exists (init scripts ran)
BACKUP_DIR="/tmp/ch_backup_YYYYMMDD_HHMMSS"

for FILE in "$BACKUP_DIR"/*.native; do
    TABLE=$(basename "$FILE" .native)
    echo "Restoring grafom.$TABLE..."
    cat "$FILE" | sudo docker exec -i grafom_clickhouse \
        clickhouse-client --query "INSERT INTO grafom.$TABLE FORMAT Native"
done
```

#### Restore Redis

```bash
# On EC2 — stop Redis, replace RDB, restart
sudo docker stop compose_redis_1
REDIS_VOL=$(sudo docker volume inspect compose_redis_data --format '{{.Mountpoint}}')
sudo cp /tmp/redis_backup_YYYYMMDD_HHMMSS.rdb "$REDIS_VOL/dump.rdb"
sudo docker start compose_redis_1

# Verify
sudo docker exec compose_redis_1 redis-cli DBSIZE
```

---

## 4. Upgrade PostgreSQL Version (15 → 16)

**Downtime:** 5-15 minutes depending on data size.
**Risk:** PostgreSQL data directory format is NOT compatible across major versions.
A direct image swap without dump/restore will fail to start.

> **Important:** Always back up first (Section 3.2).

### Step 4.1 — Pre-flight checks

```bash
ssh -i ~/grafom/login.pem ubuntu@13.51.159.243

# Current version
sudo docker exec compose_postgres_1 psql -U postgres -c "SELECT version();"

# List all databases
sudo docker exec compose_postgres_1 \
    psql -U postgres -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size FROM pg_database WHERE datname LIKE 'grafom_%' ORDER BY datname"

# Check for PostgreSQL extensions that may need upgrading
sudo docker exec compose_postgres_1 \
    psql -U postgres -c "SELECT extname, extversion FROM pg_extension"
```

### Step 4.2 — Full backup

```bash
# pg_dumpall captures everything: databases, roles, schemas, data
sudo docker exec compose_postgres_1 \
    pg_dumpall -U postgres > /tmp/pg_pre_upgrade_$(date +%Y%m%d).sql

# Verify backup size is reasonable
ls -lh /tmp/pg_pre_upgrade_*.sql
wc -l /tmp/pg_pre_upgrade_*.sql
```

### Step 4.3 — Stop and remove old container + volume

```bash
cd /opt/infra/compose

# Stop just PostgreSQL
sudo docker-compose stop postgres

# Remove the container (data volume is separate)
sudo docker-compose rm -f postgres

# Remove the old data volume (DESTRUCTIVE — backup must exist)
sudo docker volume rm compose_postgres_data
```

### Step 4.4 — Update image tag

On your Mac, edit `ec2/docker-compose.yml`:

```yaml
# Change:
  postgres:
    image: postgres:15
# To:
  postgres:
    image: postgres:16
```

Deploy with:

```bash
./ec2/deploy.sh
```

Or manually on EC2:

```bash
# Edit the compose file on EC2
sudo nano /opt/infra/compose/docker-compose.yml
# Change postgres:15 to postgres:16

# Start PostgreSQL (new empty data volume created automatically)
sudo docker-compose -f /opt/infra/compose/docker-compose.yml up -d postgres
```

### Step 4.5 — Wait for PostgreSQL to initialize

```bash
# Wait for the healthcheck to pass
sleep 10
sudo docker ps --filter "name=postgres" --format "table {{.Names}}\t{{.Status}}"
# Should show: Up ... (healthy)
```

### Step 4.6 — Restore from backup

```bash
# Restore the full dump into the new PostgreSQL 16 instance
cat /tmp/pg_pre_upgrade_*.sql | \
    sudo docker exec -i compose_postgres_1 psql -U postgres

# Also run the idempotent init script to ensure all 13 databases exist
sudo docker exec compose_postgres_1 \
    psql -U postgres -f /docker-entrypoint-initdb.d/001_create_databases.sql
```

### Step 4.7 — Verify all 13 databases intact

```bash
# List databases
sudo docker exec compose_postgres_1 \
    psql -U postgres -c "SELECT datname FROM pg_database WHERE datname LIKE 'grafom_%' ORDER BY datname"

# Expected: 13 databases (grafom_analytics, grafom_billing, grafom_execution, etc.)

# Verify version
sudo docker exec compose_postgres_1 psql -U postgres -c "SELECT version();"
# Expected: PostgreSQL 16.x

# Spot-check a known table (if identity service has been migrated)
sudo docker exec compose_postgres_1 \
    psql -U postgres -d grafom_identity -c "\dt auth_schema.*" 2>/dev/null || echo "No tables yet in grafom_identity (expected if not migrated)"
```

### Step 4.8 — Run service migrations

Each service repo manages its own schema migrations. After upgrading PostgreSQL, re-run
migrations for any services that have been deployed:

```bash
# Example for identity service (from Mac)
cd ~/grafom/grafom-identity-service
source .env.ec2
make migrate-up
```

### Rollback

If the upgrade fails, restore PostgreSQL 15:

1. Stop the PostgreSQL 16 container, remove volume
2. Change image tag back to `postgres:15`
3. Start container, restore from backup

---

## 5. Upgrade ClickHouse Version (24.8 → newer)

**Downtime:** 1-3 minutes (container restart).
**Risk:** ClickHouse is generally backward-compatible within a major version. Breaking
changes between major versions are documented in the changelog. The `toDateTime()` cast
workaround for TTL on DateTime64 columns may be resolved in newer versions.

> **Important:** Always back up first (Section 3.3).

### Step 5.1 — Check changelog for breaking changes

Before upgrading, review the ClickHouse changelog for the target version:
`https://clickhouse.com/docs/en/whats-new/changelog/`

Pay attention to:
- Changes to MergeTree table behavior
- Kafka table engine changes (used for ingestion per AB-006)
- DateTime64 / TTL behavior changes
- MaterializedView semantics

### Step 5.2 — Pre-flight checks

```bash
ssh -i ~/grafom/login.pem ubuntu@13.51.159.243

# Current version
sudo docker exec grafom_clickhouse clickhouse-client --query "SELECT version()"

# List all tables and views
sudo docker exec grafom_clickhouse \
    clickhouse-client --query "SELECT name, engine, total_rows, formatReadableSize(total_bytes) AS size FROM system.tables WHERE database = 'grafom' ORDER BY name" --format PrettyCompact

# Count (expect 20: tables + materialized views)
sudo docker exec grafom_clickhouse \
    clickhouse-client --query "SELECT count() FROM system.tables WHERE database = 'grafom'"

# Export DDL for comparison after upgrade
sudo docker exec grafom_clickhouse \
    clickhouse-client --query "SELECT name, create_table_query FROM system.tables WHERE database = 'grafom' ORDER BY name" --format TabSeparated > /tmp/ch_ddl_before.tsv
```

### Step 5.3 — Backup data

Follow Section 3.3 to back up all table data.

### Step 5.4 — Update image tag

On your Mac, edit `ec2/docker-compose.yml`:

```yaml
# Change:
  clickhouse:
    image: clickhouse/clickhouse-server:24.8-alpine
# To (example):
  clickhouse:
    image: clickhouse/clickhouse-server:24.12-alpine
```

### Step 5.5 — Deploy

```bash
# From Mac — full deploy cycle
./ec2/deploy.sh
```

Or manually on EC2:

```bash
cd /opt/infra/compose
sudo docker-compose pull clickhouse
sudo docker-compose up -d clickhouse
```

### Step 5.6 — Verify all 20 tables/views exist

```bash
# Version check
sudo docker exec grafom_clickhouse clickhouse-client --query "SELECT version()"

# Table count
sudo docker exec grafom_clickhouse \
    clickhouse-client --query "SELECT count() FROM system.tables WHERE database = 'grafom'"
# Expected: 20

# List tables
sudo docker exec grafom_clickhouse \
    clickhouse-client --query "SELECT name, engine FROM system.tables WHERE database = 'grafom' ORDER BY name" --format PrettyCompact
```

### Step 5.7 — Run test queries on each table type

```bash
# MergeTree table (market_ticks)
sudo docker exec grafom_clickhouse \
    clickhouse-client --query "SELECT count() FROM grafom.market_ticks"

# Materialized view (mv_ohlcv_1m)
sudo docker exec grafom_clickhouse \
    clickhouse-client --query "SELECT count() FROM grafom.mv_ohlcv_1m"

# OHLCV table (ohlcv_1m)
sudo docker exec grafom_clickhouse \
    clickhouse-client --query "SELECT count() FROM grafom.ohlcv_1m"

# Kafka table engine (if any exist — verify it can connect)
sudo docker exec grafom_clickhouse \
    clickhouse-client --query "SELECT name, engine FROM system.tables WHERE database = 'grafom' AND engine LIKE '%Kafka%'" --format PrettyCompact

# DDL comparison — export after and diff
sudo docker exec grafom_clickhouse \
    clickhouse-client --query "SELECT name, create_table_query FROM system.tables WHERE database = 'grafom' ORDER BY name" --format TabSeparated > /tmp/ch_ddl_after.tsv
diff /tmp/ch_ddl_before.tsv /tmp/ch_ddl_after.tsv
```

### Rollback

ClickHouse data directory is forward-compatible but not always backward-compatible.
If rollback is needed:

1. Stop the container
2. Remove the data volume: `sudo docker volume rm compose_clickhouse_data`
3. Revert image tag to `24.8-alpine`
4. Start container (init scripts recreate empty tables)
5. Restore data from backup (Section 3.3 restore procedure)

---

## 6. Upgrade Redpanda Version

**Downtime:** 1-2 minutes (container restart).
**Risk:** Low — Redpanda maintains Kafka protocol compatibility. Topics and data persist
on the `redpanda_data` volume across upgrades.

### Step 6.1 — Pre-flight checks

```bash
ssh -i ~/grafom/login.pem ubuntu@13.51.159.243

# Current version
sudo docker exec compose_redpanda_1 rpk version

# List all topics and partition counts
sudo docker exec compose_redpanda_1 rpk topic list

# Record consumer groups (if any)
sudo docker exec compose_redpanda_1 rpk group list
```

### Step 6.2 — Check compatibility

Review the Redpanda release notes for the target version:
`https://docs.redpanda.com/current/get-started/whats-new/`

Key concerns:
- Kafka protocol version compatibility with your service clients
- Data directory format changes (rare, documented if breaking)
- rpk CLI changes

### Step 6.3 — Update image tag

On your Mac, edit `ec2/docker-compose.yml`:

```yaml
# Change (if pinning to a specific version):
  redpanda:
    image: redpandadata/redpanda:latest
# To:
  redpanda:
    image: redpandadata/redpanda:v24.3.1    # or desired version
```

> **Note:** The current compose uses `latest`. To pin a specific version (recommended for
> stability), replace `latest` with a version tag.

### Step 6.4 — Deploy

```bash
# From Mac
./ec2/deploy.sh

# Or manually on EC2
cd /opt/infra/compose
sudo docker-compose pull redpanda
sudo docker-compose up -d redpanda
```

### Step 6.5 — Verify topics and partition counts

```bash
# Version
sudo docker exec compose_redpanda_1 rpk version

# Topics (should match pre-upgrade list — 25 topics)
sudo docker exec compose_redpanda_1 rpk topic list

# Spot-check a topic's partition count
sudo docker exec compose_redpanda_1 rpk topic describe market.instrument.tick.v1
# Expected: 6 partitions

# Consumer groups (should match pre-upgrade list)
sudo docker exec compose_redpanda_1 rpk group list

# Cluster health
sudo docker exec compose_redpanda_1 rpk cluster health
```

### Rollback

Topics persist on the volume. To rollback:

1. Revert image tag in `docker-compose.yml`
2. `sudo docker-compose up -d redpanda`
3. Verify topics still intact

---

## 7. Emergency: Recover from Corrupted Volume

**Downtime:** 10-30 minutes depending on which volume is corrupted and backup size.
**Risk:** Data loss if no backup exists. Init scripts recreate empty schemas but not data.

### Step 7.1 — Identify the corrupted volume

```bash
ssh -i ~/grafom/login.pem ubuntu@13.51.159.243

# Check which containers are failing
sudo docker ps -a --format "table {{.Names}}\t{{.Status}}"

# Check logs for the failing container
sudo docker logs compose_postgres_1 --tail=50     # PostgreSQL
sudo docker logs grafom_clickhouse --tail=50       # ClickHouse
sudo docker logs compose_redis_1 --tail=50         # Redis
sudo docker logs compose_redpanda_1 --tail=50      # Redpanda

# Common error signatures:
#   PostgreSQL:  "database files are incompatible with server"
#   ClickHouse:  "Cannot attach table ... data is corrupted"
#   Redis:       "Bad file format reading the append only file"
#   Redpanda:    "crash loop", "failed to recover log segment"
```

### Step 7.2 — Stop all containers

```bash
cd /opt/infra/compose
sudo docker-compose down
```

### Step 7.3 — Remove the corrupted volume

```bash
# Identify the volume name
sudo docker volume ls

# Remove ONLY the corrupted volume
# Replace <volume_name> with the specific volume (e.g., compose_postgres_data)
sudo docker volume rm <volume_name>

# DO NOT run `docker volume prune` — this removes ALL unused volumes
```

### Step 7.4 — Recreate and restore

#### PostgreSQL recovery

```bash
# Start PostgreSQL (creates fresh data volume, init scripts run automatically)
sudo docker-compose -f /opt/infra/compose/docker-compose.yml up -d postgres

# Wait for healthy
sleep 15
sudo docker ps --filter "name=postgres" --format "table {{.Names}}\t{{.Status}}"

# Init scripts create the 13 databases. Restore data if backup exists:
cat /tmp/pg_backup_YYYYMMDD_HHMMSS.sql | \
    sudo docker exec -i compose_postgres_1 psql -U postgres

# Re-run service migrations (from Mac, for each deployed service)
# cd ~/grafom/<service-repo> && source .env.ec2 && make migrate-up
```

#### ClickHouse recovery

```bash
# Start ClickHouse (creates fresh data volume, init SQL runs automatically)
sudo docker-compose -f /opt/infra/compose/docker-compose.yml up -d clickhouse

# Wait for healthy
sleep 15

# Verify 20 tables/views recreated (empty)
sudo docker exec grafom_clickhouse \
    clickhouse-client --query "SELECT count() FROM system.tables WHERE database = 'grafom'"

# Restore data if backup exists (Section 3.3 restore procedure)
```

#### Redis recovery

```bash
# Start Redis (creates fresh data volume — all cached data is lost)
sudo docker-compose -f /opt/infra/compose/docker-compose.yml up -d redis

# Redis is a cache — data loss is acceptable. Services will repopulate.
# If backup exists and you need the data:
sudo docker stop compose_redis_1
REDIS_VOL=$(sudo docker volume inspect compose_redis_data --format '{{.Mountpoint}}')
sudo cp /tmp/redis_backup_YYYYMMDD_HHMMSS.rdb "$REDIS_VOL/dump.rdb"
sudo docker start compose_redis_1
```

#### Redpanda recovery

```bash
# Start Redpanda (creates fresh data volume — all topic data is lost)
sudo docker-compose -f /opt/infra/compose/docker-compose.yml up -d redpanda

# Wait for healthy
sleep 20

# Re-create topics (topic definitions are lost with the volume)
sudo docker cp /opt/infra/kafka/init/create-topics.sh compose_redpanda_1:/tmp/create-topics.sh
sudo docker exec compose_redpanda_1 bash /tmp/create-topics.sh

# Verify 25 topics
sudo docker exec compose_redpanda_1 rpk topic list
```

### Step 7.5 — Start remaining services and verify

```bash
# Start everything
sudo docker-compose -f /opt/infra/compose/docker-compose.yml up -d

# Verify all 6 containers running
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Memory check
free -m
sudo docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}"
```

### Step 7.6 — Notify service teams

If data was lost, notify service teams to:
1. Re-run database migrations against PostgreSQL
2. Verify ClickHouse table schemas match their expectations
3. Re-seed any required test data
4. Restart services to re-establish Kafka consumer group offsets

---

## Related

- [architecture.md](./architecture.md) — Infrastructure evolution phases
- [ec2/security-group.md](../ec2/security-group.md) — Security group rules
- [ec2/deploy.sh](../ec2/deploy.sh) — Deployment script
- [run-070](https://github.com/grafom-markets/grafom-architecture-hub/blob/main/docs/runbooks/run-070-ec2-infrastructure-setup.md) — EC2 setup runbook (initial setup, §9 RAM budget)
