-- Market data tables (ctx-020: Market Intelligence)
-- Source: market-ingestion-service via Kafka topics
-- Per arc-180 Section 2-3

-- Raw tick data — ingested from market.instrument.tick.v1
CREATE TABLE IF NOT EXISTS grafom.market_ticks (
    symbol       LowCardinality(String),
    exchange     LowCardinality(String),
    price        Float64   CODEC(Gorilla, LZ4),
    volume       UInt64    CODEC(T64, LZ4),
    bid          Float64   CODEC(Gorilla, LZ4),
    ask          Float64   CODEC(Gorilla, LZ4),
    timestamp    DateTime64(3, 'Asia/Kolkata') CODEC(DoubleDelta, LZ4)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (symbol, timestamp)
TTL toDateTime(timestamp) + INTERVAL 90 DAY DELETE
SETTINGS index_granularity = 8192;

-- 1-minute OHLCV bars — materialized from ticks
CREATE TABLE IF NOT EXISTS grafom.ohlcv_1m (
    symbol       LowCardinality(String),
    bucket       DateTime64(0, 'Asia/Kolkata') CODEC(DoubleDelta, LZ4),
    open         Float64   CODEC(Gorilla, LZ4),
    high         Float64   CODEC(Gorilla, LZ4),
    low          Float64   CODEC(Gorilla, LZ4),
    close        Float64   CODEC(Gorilla, LZ4),
    volume       UInt64    CODEC(T64, LZ4),
    tick_count   UInt32    CODEC(T64, LZ4)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(bucket)
ORDER BY (symbol, bucket)
TTL toDateTime(bucket) + INTERVAL 1 YEAR DELETE;

-- 5-minute OHLCV bars
CREATE TABLE IF NOT EXISTS grafom.ohlcv_5m (
    symbol       LowCardinality(String),
    bucket       DateTime64(0, 'Asia/Kolkata') CODEC(DoubleDelta, LZ4),
    open         Float64   CODEC(Gorilla, LZ4),
    high         Float64   CODEC(Gorilla, LZ4),
    low          Float64   CODEC(Gorilla, LZ4),
    close        Float64   CODEC(Gorilla, LZ4),
    volume       UInt64    CODEC(T64, LZ4),
    tick_count   UInt32    CODEC(T64, LZ4)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(bucket)
ORDER BY (symbol, bucket)
TTL toDateTime(bucket) + INTERVAL 3 YEAR DELETE;

-- 1-hour OHLCV bars
CREATE TABLE IF NOT EXISTS grafom.ohlcv_1h (
    symbol       LowCardinality(String),
    bucket       DateTime64(0, 'Asia/Kolkata') CODEC(DoubleDelta, LZ4),
    open         Float64   CODEC(Gorilla, LZ4),
    high         Float64   CODEC(Gorilla, LZ4),
    low          Float64   CODEC(Gorilla, LZ4),
    close        Float64   CODEC(Gorilla, LZ4),
    volume       UInt64    CODEC(T64, LZ4),
    tick_count   UInt32    CODEC(T64, LZ4)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(bucket)
ORDER BY (symbol, bucket);
-- No TTL — 7-year retention (SEBI)

-- 1-day OHLCV bars
CREATE TABLE IF NOT EXISTS grafom.ohlcv_1d (
    symbol       LowCardinality(String),
    bucket       Date CODEC(DoubleDelta, LZ4),
    open         Float64   CODEC(Gorilla, LZ4),
    high         Float64   CODEC(Gorilla, LZ4),
    low          Float64   CODEC(Gorilla, LZ4),
    close        Float64   CODEC(Gorilla, LZ4),
    volume       UInt64    CODEC(T64, LZ4),
    tick_count   UInt32    CODEC(T64, LZ4)
) ENGINE = MergeTree()
PARTITION BY toYear(bucket)
ORDER BY (symbol, bucket);
-- No TTL — permanent retention

-- Options chain snapshots
CREATE TABLE IF NOT EXISTS grafom.options_chain_snapshots (
    underlying     LowCardinality(String),
    expiry         Date,
    strike         Float64,
    option_type    LowCardinality(String),  -- 'CE' or 'PE'
    ltp            Float64   CODEC(Gorilla, LZ4),
    bid            Float64   CODEC(Gorilla, LZ4),
    ask            Float64   CODEC(Gorilla, LZ4),
    open_interest  UInt64    CODEC(T64, LZ4),
    volume         UInt64    CODEC(T64, LZ4),
    iv             Float64   CODEC(Gorilla, LZ4),
    delta          Float64   CODEC(Gorilla, LZ4),
    gamma          Float64   CODEC(Gorilla, LZ4),
    theta          Float64   CODEC(Gorilla, LZ4),
    vega           Float64   CODEC(Gorilla, LZ4),
    snapshot_time  DateTime64(3, 'Asia/Kolkata') CODEC(DoubleDelta, LZ4)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(snapshot_time)
ORDER BY (underlying, expiry, strike, option_type, snapshot_time)
TTL toDateTime(snapshot_time) + INTERVAL 90 DAY DELETE;

-- Regime snapshots
CREATE TABLE IF NOT EXISTS grafom.regime_snapshots (
    symbol          LowCardinality(String),
    regime          LowCardinality(String),  -- 'trending_up', 'trending_down', 'range_bound', 'volatile'
    confidence      Float32,
    volatility_20d  Float64   CODEC(Gorilla, LZ4),
    timestamp       DateTime64(3, 'Asia/Kolkata') CODEC(DoubleDelta, LZ4)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (symbol, timestamp)
TTL toDateTime(timestamp) + INTERVAL 1 YEAR DELETE;
