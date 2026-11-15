-- Sift telemetry. Same shape as Headroom's, schema 1 of Sift's batch.

CREATE TABLE IF NOT EXISTS telemetry_batches (
  batch_id TEXT PRIMARY KEY,
  received_at TEXT NOT NULL,
  period TEXT NOT NULL,
  dedupe_key TEXT NOT NULL,
  app_version TEXT NOT NULL,
  macos_major INTEGER NOT NULL,
  architecture TEXT NOT NULL,
  country TEXT,
  payload TEXT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS telemetry_batches_period_dedupe
  ON telemetry_batches (period, dedupe_key);
CREATE INDEX IF NOT EXISTS telemetry_batches_period ON telemetry_batches (period);

-- The growth series. Never pruned: a row is a week, a count of Macs and the
-- new / returning / reactivated split. No column describes a Mac.
CREATE TABLE IF NOT EXISTS telemetry_periods (
  period TEXT PRIMARY KEY,
  batch_count INTEGER NOT NULL DEFAULT 0,
  new_macs INTEGER NOT NULL DEFAULT 0,
  returning_macs INTEGER NOT NULL DEFAULT 0,
  reactivated_macs INTEGER NOT NULL DEFAULT 0,
  last_received_at TEXT NOT NULL
);

-- Per-week breakdowns. Expire with the raw batches after 180 days.
CREATE TABLE IF NOT EXISTS telemetry_dimensions (
  period TEXT NOT NULL,
  dimension TEXT NOT NULL,
  item TEXT NOT NULL,
  sample_count INTEGER NOT NULL DEFAULT 0,
  value_total REAL NOT NULL DEFAULT 0,
  PRIMARY KEY (period, dimension, item)
);

CREATE INDEX IF NOT EXISTS telemetry_dimensions_period ON telemetry_dimensions (period);
