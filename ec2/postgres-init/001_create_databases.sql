-- 001_create_databases.sql
-- Idempotent creation of all 13 per-service PostgreSQL databases.
--
-- PostgreSQL has no CREATE DATABASE IF NOT EXISTS. We use psql's \gexec to
-- conditionally execute CREATE DATABASE only when the database is absent.
--
-- Runs automatically on first Postgres start (docker-entrypoint-initdb.d).
-- For existing instances, run manually:
--   docker exec compose_postgres_1 psql -U postgres \
--       -f /docker-entrypoint-initdb.d/001_create_databases.sql
--
-- References: arc-050 (three-tier data architecture), svc-010 (service matrix)

-- ctx-080 User & Identity — users, sessions, RBAC roles, onboarding state
SELECT 'CREATE DATABASE grafom_identity OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'grafom_identity')
\gexec

-- ctx-020 Market Intelligence — reference data ingestion (instruments, exchanges)
SELECT 'CREATE DATABASE grafom_market_ingestion OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'grafom_market_ingestion')
\gexec

-- ctx-020 Market Intelligence — reference data (instruments, exchanges), regime/IV
SELECT 'CREATE DATABASE grafom_market_intelligence OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'grafom_market_intelligence')
\gexec

-- ctx-030 Strategy Engine — strategy definitions, parameters, versions, backtest configs
SELECT 'CREATE DATABASE grafom_strategy_engine OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'grafom_strategy_engine')
\gexec

-- ctx-040 Signal & Scoring — signal definitions, OLTP scoring state
SELECT 'CREATE DATABASE grafom_signal_scoring OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'grafom_signal_scoring')
\gexec

-- ctx-050 Execution — orders, positions, fills, trade history
SELECT 'CREATE DATABASE grafom_execution OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'grafom_execution')
\gexec

-- ctx-060 Risk Management — risk configs, limits, breach history
SELECT 'CREATE DATABASE grafom_risk OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'grafom_risk')
\gexec

-- ctx-070 Broker Gateway — broker credentials (AES-256-GCM), connection config
SELECT 'CREATE DATABASE grafom_broker_gateway OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'grafom_broker_gateway')
\gexec

-- ctx-090 Dashboard BFF — read model cache (no OLTP tables; gRPC reads from other services)
SELECT 'CREATE DATABASE grafom_dashboard_bff OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'grafom_dashboard_bff')
\gexec

-- ctx-110 Notifications — templates, delivery log, preferences
SELECT 'CREATE DATABASE grafom_notification OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'grafom_notification')
\gexec

-- ctx-100 Billing — subscriptions, invoices, payment history, entitlements
SELECT 'CREATE DATABASE grafom_billing OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'grafom_billing')
\gexec

-- ctx-130 Compliance — audit trail (append-only), consent records, data deletion requests
SELECT 'CREATE DATABASE grafom_compliance OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'grafom_compliance')
\gexec

-- ctx-120 Reporting & Tax — report metadata, tax lots (OLTP)
SELECT 'CREATE DATABASE grafom_reporting OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'grafom_reporting')
\gexec

-- Verify
\echo '--- Grafom databases ---'
SELECT datname FROM pg_database WHERE datname LIKE 'grafom_%' ORDER BY datname;
