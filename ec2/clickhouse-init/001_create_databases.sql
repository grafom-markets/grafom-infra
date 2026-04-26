-- ClickHouse initialization: create the grafom database and base tables.
-- This file runs automatically when the container starts for the first time
-- (via /docker-entrypoint-initdb.d/).
--
-- Per arc-180: ClickHouse is Tier 2 (time-series and analytics).
-- All data arrives via Kafka engine tables from Redpanda/Kafka topics.

CREATE DATABASE IF NOT EXISTS grafom;
