-- Materialized views for OHLCV bar aggregation hierarchy
-- Per arc-180 Section 3: ticks → 1m → 5m → 1h → 1d
-- These trigger on insert (real-time), not on a polling schedule.

-- Ticks → 1-minute bars
CREATE MATERIALIZED VIEW IF NOT EXISTS grafom.mv_ohlcv_1m TO grafom.ohlcv_1m AS
SELECT
    symbol,
    toStartOfMinute(timestamp)   AS bucket,
    argMin(price, timestamp)     AS open,
    max(price)                   AS high,
    min(price)                   AS low,
    argMax(price, timestamp)     AS close,
    sum(volume)                  AS volume,
    count()                      AS tick_count
FROM grafom.market_ticks
GROUP BY symbol, bucket;

-- 1-minute bars → 5-minute bars
CREATE MATERIALIZED VIEW IF NOT EXISTS grafom.mv_ohlcv_5m TO grafom.ohlcv_5m AS
SELECT
    symbol,
    toStartOfFiveMinutes(bucket) AS bucket,
    argMin(open, bucket)         AS open,
    max(high)                    AS high,
    min(low)                     AS low,
    argMax(close, bucket)        AS close,
    sum(volume)                  AS volume,
    sum(tick_count)              AS tick_count
FROM grafom.ohlcv_1m
GROUP BY symbol, bucket;

-- 5-minute bars → 1-hour bars
CREATE MATERIALIZED VIEW IF NOT EXISTS grafom.mv_ohlcv_1h TO grafom.ohlcv_1h AS
SELECT
    symbol,
    toStartOfHour(bucket)  AS bucket,
    argMin(open, bucket)   AS open,
    max(high)              AS high,
    min(low)               AS low,
    argMax(close, bucket)  AS close,
    sum(volume)            AS volume,
    sum(tick_count)        AS tick_count
FROM grafom.ohlcv_5m
GROUP BY symbol, bucket;

-- 1-hour bars → 1-day bars
CREATE MATERIALIZED VIEW IF NOT EXISTS grafom.mv_ohlcv_1d TO grafom.ohlcv_1d AS
SELECT
    symbol,
    toDate(bucket)         AS bucket,
    argMin(open, bucket)   AS open,
    max(high)              AS high,
    min(low)               AS low,
    argMax(close, bucket)  AS close,
    sum(volume)            AS volume,
    sum(tick_count)        AS tick_count
FROM grafom.ohlcv_1h
GROUP BY symbol, bucket;
