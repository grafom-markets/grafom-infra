-- Signal scoring and reporting tables (ctx-040, ctx-120)
-- Per arc-180 Section 2

-- Score history — ingested from signal.score.updated.v1
CREATE TABLE IF NOT EXISTS grafom.score_history (
    signal_id       String,
    strategy_id     LowCardinality(String),
    symbol          LowCardinality(String),
    composite_score Float32   CODEC(Gorilla, LZ4),
    confidence      Float32   CODEC(Gorilla, LZ4),
    regime          LowCardinality(String),
    scored_at       DateTime64(3, 'Asia/Kolkata') CODEC(DoubleDelta, LZ4)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(scored_at)
ORDER BY (strategy_id, signal_id, scored_at)
TTL toDateTime(scored_at) + INTERVAL 1 YEAR DELETE;

-- Hourly score aggregates
CREATE TABLE IF NOT EXISTS grafom.scores_1h (
    strategy_id     LowCardinality(String),
    signal_id       String,
    bucket          DateTime64(0, 'Asia/Kolkata') CODEC(DoubleDelta, LZ4),
    avg_score       Float32,
    min_score       Float32,
    max_score       Float32,
    sample_count    UInt32
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(bucket)
ORDER BY (strategy_id, signal_id, bucket)
TTL toDateTime(bucket) + INTERVAL 3 YEAR DELETE;

-- Materialized view: scores → hourly aggregates
CREATE MATERIALIZED VIEW IF NOT EXISTS grafom.mv_scores_1h TO grafom.scores_1h AS
SELECT
    strategy_id,
    signal_id,
    toStartOfHour(scored_at) AS bucket,
    avg(composite_score)     AS avg_score,
    min(composite_score)     AS min_score,
    max(composite_score)     AS max_score,
    count()                  AS sample_count
FROM grafom.score_history
GROUP BY strategy_id, signal_id, bucket;

-- Fills archive — ingested from execution.order.filled.v1
-- Analytics copy of execution fills for reporting and tax (SEBI 7-year retention)
CREATE TABLE IF NOT EXISTS grafom.fills (
    fill_id        String,
    order_id       String,
    user_id        String,
    symbol         LowCardinality(String),
    exchange       LowCardinality(String),
    side           LowCardinality(String),  -- 'buy' or 'sell'
    quantity       UInt32,
    price          Float64    CODEC(Gorilla, LZ4),
    fees           Float64    CODEC(Gorilla, LZ4),
    instrument_type LowCardinality(String), -- 'OPTIONS', 'FUTURES', 'EQUITY', 'CRYPTO'
    filled_at      DateTime64(3, 'Asia/Kolkata') CODEC(DoubleDelta, LZ4)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(filled_at)
ORDER BY (user_id, filled_at);
-- No TTL — 7-year retention (SEBI)

-- P&L time-series — ingested from reporting events
CREATE TABLE IF NOT EXISTS grafom.pnl_series (
    user_id          String,
    strategy_id      LowCardinality(String),
    realized_pnl     Float64    CODEC(Gorilla, LZ4),
    unrealized_pnl   Float64    CODEC(Gorilla, LZ4),
    running_balance  Float64    CODEC(Gorilla, LZ4),
    running_drawdown Float64    CODEC(Gorilla, LZ4),
    timestamp        DateTime64(3, 'Asia/Kolkata') CODEC(DoubleDelta, LZ4)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (user_id, strategy_id, timestamp)
TTL toDateTime(timestamp) + INTERVAL 3 YEAR DELETE;

-- Daily P&L aggregates
CREATE TABLE IF NOT EXISTS grafom.pnl_daily (
    user_id       String,
    strategy_id   LowCardinality(String),
    date          Date CODEC(DoubleDelta, LZ4),
    daily_pnl     Float64,
    min_balance   Float64,
    max_balance   Float64,
    max_drawdown  Float64
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (user_id, strategy_id, date);
-- No TTL — 7-year retention (Tax, SEBI)

-- Materialized view: P&L → daily aggregates
CREATE MATERIALIZED VIEW IF NOT EXISTS grafom.mv_pnl_daily TO grafom.pnl_daily AS
SELECT
    user_id,
    strategy_id,
    toDate(timestamp)           AS date,
    sum(realized_pnl)           AS daily_pnl,
    min(running_balance)        AS min_balance,
    max(running_balance)        AS max_balance,
    max(running_drawdown)       AS max_drawdown
FROM grafom.pnl_series
GROUP BY user_id, strategy_id, date;

-- Risk snapshots — ingested from risk.position.updated.v1
CREATE TABLE IF NOT EXISTS grafom.risk_snapshots (
    user_id         String,
    total_exposure  Float64    CODEC(Gorilla, LZ4),
    margin_used     Float64    CODEC(Gorilla, LZ4),
    daily_loss      Float64    CODEC(Gorilla, LZ4),
    position_count  UInt16,
    timestamp       DateTime64(3, 'Asia/Kolkata') CODEC(DoubleDelta, LZ4)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (user_id, timestamp)
TTL toDateTime(timestamp) + INTERVAL 1 YEAR DELETE;

-- Performance metrics
CREATE TABLE IF NOT EXISTS grafom.performance_metrics (
    user_id        String,
    strategy_id    LowCardinality(String),
    metric_name    LowCardinality(String),  -- 'sharpe', 'sortino', 'max_drawdown', 'win_rate', etc.
    metric_value   Float64    CODEC(Gorilla, LZ4),
    period         LowCardinality(String),  -- 'daily', 'weekly', 'monthly', 'ytd'
    computed_at    DateTime64(3, 'Asia/Kolkata') CODEC(DoubleDelta, LZ4)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(computed_at)
ORDER BY (user_id, strategy_id, metric_name, computed_at)
TTL toDateTime(computed_at) + INTERVAL 3 YEAR DELETE;
