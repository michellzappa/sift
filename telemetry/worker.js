// Sift telemetry intake and Community Pulse. Ported from Headroom's Worker.
// The client contract is Sift/Telemetry/Telemetry.swift; the privacy
// contract is docs/telemetry.md. Every field is whitelisted before storage.
// Request headers and IP addresses are never stored.
import { communityPage } from "./community_page.js";
import { KNOWN_FEEDS, KNOWN_FEEDS_VERSION, KNOWN_FEED_IDS } from "./known_feeds.js";

const ALLOWED_SOURCES = new Set([
  "safari", "chrome", "reading-list", "instagram", "tiktok", "x", "import", "feed",
]);
const ALLOWED_DESTINATIONS = new Set([
  "starlings", "obsidian", "markdown", "reading-list",
]);
// FeedProvider ids in the Mac app (Sift/Feeds/Providers), plus "web".
const ALLOWED_FEED_KINDS = new Set([
  "web", "reddit", "youtube", "substack", "bluesky", "mastodon", "medium",
  "tumblr", "github", "podcast", "hackernews", "news", "arxiv",
]);
// A well-known feed shows on the Community Pulse only when at least this
// many Macs follow it in a week (its own floor; the rest of the page uses 1).
const KNOWN_FEED_MINIMUM_GROUP_SIZE = 5;
const ALLOWED_BACKENDS = new Set(["claude-code", "api"]);
const ALLOWED_LINK_BUCKETS = new Set(["0", "1-99", "100-999", "1000-9999", "10000+"]);
const ALLOWED_THEME_BUCKETS = new Set(["0", "1-4", "5-9", "10-19", "20+"]);
const ALLOWED_FEATURES = new Set([
  "themes", "on_device_model", "local_first_pass", "local_summaries",
  "youtube_transcripts", "reel_transcripts", "youtube_audio", "connections",
  "close_after_send",
]);

// Retention without a cross-week identifier: the Mac sends one word.
const ALLOWED_COHORTS = new Set(["new", "returning", "reactivated"]);
const COHORT_COLUMNS = {
  new: "new_macs",
  returning: "returning_macs",
  reactivated: "reactivated_macs",
};

const COMMUNITY_MINIMUM_GROUP_SIZE = 1;
// Raw batches and per-week breakdowns expire after this; weekly counts stay.
const COMMUNITY_WINDOW_DAYS = 180;
const COMMUNITY_HISTORY_WEEKS = 52;
const REPO = "michellzappa/sift";

function json(body, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      ...extraHeaders,
    },
  });
}

function boundedString(value, max = 80) {
  return typeof value === "string" && value.length > 0 && value.length <= max
    ? value
    : null;
}

function allowedList(value, allowed) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.filter((item) =>
    typeof item === "string" && allowed.has(item)))].sort();
}

function sanitize(payload) {
  if (!payload || typeof payload !== "object") return null;
  const batchID = boundedString(payload.batch_id, 80);
  const period = boundedString(payload.period, 12);
  const dedupeKey = typeof payload.dedupe_key === "string"
      && /^[0-9a-f]{64}$/.test(payload.dedupe_key)
    ? payload.dedupe_key
    : null;
  const cohort = ALLOWED_COHORTS.has(payload.cohort) ? payload.cohort : null;
  const app = payload.app;
  if (payload.schema !== 1 || !batchID || !period || !dedupeKey
      || !/^\d{4}-W(?:0[1-9]|[1-4]\d|5[0-3])$/.test(period)) {
    return null;
  }
  if (!app || typeof app !== "object") return null;
  const version = boundedString(app.version, 32);
  const build = boundedString(app.build, 64);
  const architecture = ["arm64", "x86_64", "unknown"].includes(app.architecture)
    ? app.architecture : "unknown";
  const macosMajor = Number.isInteger(app.macos_major) && app.macos_major >= 10 && app.macos_major <= 99
    ? app.macos_major : null;
  if (!version || !build || macosMajor === null) return null;

  const features = {};
  if (payload.features && typeof payload.features === "object") {
    for (const [key, value] of Object.entries(payload.features)) {
      if (ALLOWED_FEATURES.has(key) && typeof value === "boolean") features[key] = value;
    }
  }
  const scale = payload.scale && typeof payload.scale === "object" ? payload.scale : {};
  const safe = {
    schema: 1,
    batch_id: batchID,
    dedupe_key: dedupeKey,
    period,
    cohort,
    app: { version, build, macos_major: macosMajor, architecture },
    sources: allowedList(payload.sources, ALLOWED_SOURCES),
    destinations: allowedList(payload.destinations, ALLOWED_DESTINATIONS),
    backend: ALLOWED_BACKENDS.has(payload.backend) ? payload.backend : null,
    scale: {
      links: ALLOWED_LINK_BUCKETS.has(scale.links) ? scale.links : null,
      themes: ALLOWED_THEME_BUCKETS.has(scale.themes) ? scale.themes : null,
    },
    features,
    feed_kinds: allowedList(payload.feed_kinds, ALLOWED_FEED_KINDS),
    known_feeds: allowedList(payload.known_feeds, KNOWN_FEED_IDS).slice(0, 100),
  };
  return JSON.stringify(safe).length <= 8192 ? safe : null;
}

function publicCount(count) {
  return count >= COMMUNITY_MINIMUM_GROUP_SIZE ? count : null;
}

function compareAppVersions(left, right) {
  const parts = (value) => String(value).split(".").map((part) => {
    const number = Number.parseInt(part, 10);
    return Number.isFinite(number) ? number : 0;
  });
  const a = parts(left);
  const b = parts(right);
  for (let index = 0; index < Math.max(a.length, b.length); index += 1) {
    const delta = (a[index] ?? 0) - (b[index] ?? 0);
    if (delta !== 0) return delta;
  }
  return 0;
}

/** X.Y.Z only, and never ahead of the latest GitHub release. */
function publishableAppVersions(versions, maxVersion) {
  return versions.filter((row) => {
    if (!/^\d+\.\d+\.\d+$/.test(row.name)) return false;
    return !(maxVersion && compareAppVersions(row.name, maxVersion) > 0);
  });
}

function dimensionRows(rows, dimension, period) {
  return rows
    .filter((row) => row.dimension === dimension && row.period === period)
    .map((row) => ({
      name: row.item,
      count: Number(row.sample_count),
      value: Number(row.value_total),
    }));
}

function countedItems(rows) {
  return rows
    .filter((row) => row.count >= COMMUNITY_MINIMUM_GROUP_SIZE)
    .sort((lhs, rhs) => rhs.count - lhs.count || lhs.name.localeCompare(rhs.name))
    .map((row) => ({ name: row.name, count: row.count }));
}

/** ISO week label for a UTC date, matching the Mac client's period format. */
function isoWeekPeriod(date) {
  const utc = new Date(Date.UTC(
    date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  utc.setUTCDate(utc.getUTCDate() + 4 - (utc.getUTCDay() || 7));
  const yearStart = new Date(Date.UTC(utc.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((utc - yearStart) / 86400000) + 1) / 7);
  return `${utc.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

/**
 * Every ISO week from the first report to now, oldest first. Empty weeks
 * publish as count: null. The newest week is `in_progress`: a Mac reports at
 * its first launch in a week, so that bar fills over seven days.
 */
function paddedWeeklyActive(observed, weeks = COMMUNITY_HISTORY_WEEKS) {
  const byPeriod = new Map(observed.map((row) => [row.period, row]));
  const end = new Date();
  const start = new Date(end.getTime() - weeks * 7 * 86400000);
  const periods = [];
  const cursor = new Date(Date.UTC(
    start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate()));
  const last = new Date(Date.UTC(
    end.getUTCFullYear(), end.getUTCMonth(), end.getUTCDate()));
  while (cursor <= last) {
    const period = isoWeekPeriod(cursor);
    if (periods[periods.length - 1] !== period) periods.push(period);
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  const first = periods.findIndex((period) => byPeriod.has(period));
  const axis = first < 0 ? periods.slice(-1) : periods.slice(first);
  const current = isoWeekPeriod(end);
  return axis.map((period) => {
    const row = byPeriod.get(period) ?? null;
    return {
      period,
      count: row ? publicCount(row.count) : null,
      in_progress: period === current,
      new_macs: row ? publicCount(row.new) : null,
      returning_macs: row ? publicCount(row.returning) : null,
      reactivated_macs: row ? publicCount(row.reactivated) : null,
    };
  });
}

async function batchColumnCounts(env, period, column) {
  if (column !== "architecture" && column !== "macos_major" && column !== "country") {
    return [];
  }
  const result = await env.DB.prepare(
    `SELECT CAST(${column} AS TEXT) AS item, COUNT(*) AS sample_count
     FROM telemetry_batches
     WHERE period = ? AND ${column} IS NOT NULL AND ${column} != ''
     GROUP BY ${column}`
  ).bind(period).all();
  return countedItems((result.results ?? []).map((row) => ({
    name: String(row.item),
    count: Number(row.sample_count),
  })));
}

/** ISO-3166 alpha-2 from Cloudflare's edge geo. Never stores the IP. */
function requestCountry(request) {
  const raw = request.cf && typeof request.cf.country === "string"
    ? request.cf.country.toUpperCase()
    : null;
  if (!raw || raw === "XX" || raw === "T1") return null;
  return /^[A-Z]{2}$/.test(raw) ? raw : null;
}

/** The latest GitHub release, as X.Y.Z. */
async function latestRelease() {
  try {
    const response = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: { Accept: "application/vnd.github+json", "User-Agent": "sift-telemetry" },
      cf: { cacheTtl: 600 },
    });
    if (!response.ok) return null;
    const doc = await response.json();
    const tag = typeof doc?.tag_name === "string" ? doc.tag_name.replace(/^v/, "") : "";
    if (!tag) return null;
    return {
      version: tag.slice(0, 32),
      published: typeof doc.published_at === "string" ? doc.published_at.slice(0, 40) : null,
    };
  } catch {
    return null;
  }
}

async function communityStats(env) {
  const periodsResult = await env.DB.prepare(
    `SELECT period, batch_count, new_macs, returning_macs, reactivated_macs
     FROM telemetry_periods ORDER BY period DESC LIMIT ?`
  ).bind(COMMUNITY_HISTORY_WEEKS).all();
  const periods = (periodsResult.results ?? []).map((row) => ({
    period: row.period,
    count: Number(row.batch_count),
    new: Number(row.new_macs ?? 0),
    returning: Number(row.returning_macs ?? 0),
    reactivated: Number(row.reactivated_macs ?? 0),
  }));
  const weeklyActiveMacs = paddedWeeklyActive(periods);
  const release = await latestRelease();
  const latest = periods[0];
  const base = {
    schema: 1,
    generated_on: new Date().toISOString().slice(0, 10),
    privacy: { minimum_group_size: COMMUNITY_MINIMUM_GROUP_SIZE },
    weekly_active_macs: weeklyActiveMacs,
    latest_release: release,
  };
  if (!latest) return { ...base, latest: null };

  const dimensionsResult = await env.DB.prepare(
    `SELECT period, dimension, item, sample_count, value_total
     FROM telemetry_dimensions WHERE period = ?`
  ).bind(latest.period).all();
  const rows = dimensionsResult.results ?? [];
  const items = (dimension) => countedItems(dimensionRows(rows, dimension, latest.period));
  const [architectures, macosMajors, countries] = await Promise.all([
    batchColumnCounts(env, latest.period, "architecture"),
    batchColumnCounts(env, latest.period, "macos_major"),
    batchColumnCounts(env, latest.period, "country"),
  ]);
  const features = dimensionRows(rows, "feature", latest.period)
    .filter((row) => row.count >= COMMUNITY_MINIMUM_GROUP_SIZE)
    .map((row) => ({ name: row.name, adoption: Math.round(row.value / row.count * 100) }))
    .sort((lhs, rhs) => lhs.name.localeCompare(rhs.name));

  return {
    ...base,
    latest: {
      period: latest.period,
      in_progress: latest.period === isoWeekPeriod(new Date()),
      reporting_macs: publicCount(latest.count),
      versions: publishableAppVersions(items("version"), release?.version ?? null),
      architectures,
      macos_majors: macosMajors,
      countries,
      sources: items("source"),
      destinations: items("destination"),
      backends: items("backend"),
      library_sizes: items("links"),
      theme_counts: items("themes"),
      features,
      feed_kinds: items("feed_kind"),
      known_feeds: countedItems(dimensionRows(rows, "known_feed", latest.period))
        .filter((row) => row.count >= KNOWN_FEED_MINIMUM_GROUP_SIZE)
        .map((row) => ({
          name: KNOWN_FEEDS.find((feed) => feed.id === row.name)?.name ?? row.name,
          count: row.count,
        })),
      known_feed_minimum_group_size: KNOWN_FEED_MINIMUM_GROUP_SIZE,
    },
  };
}

function upsertDimension(env, period, dimension, item, valueTotal = 0) {
  return env.DB.prepare(
    `INSERT INTO telemetry_dimensions (period, dimension, item, sample_count, value_total)
     VALUES (?, ?, ?, 1, ?)
     ON CONFLICT(period, dimension, item) DO UPDATE SET
       sample_count = sample_count + 1,
       value_total = value_total + excluded.value_total`
  ).bind(period, dimension, item, valueTotal);
}

async function recordRollups(env, safe, receivedAt, country) {
  // Fixed map, never the client string, so the column name cannot be steered.
  const cohortColumn = safe.cohort ? COHORT_COLUMNS[safe.cohort] : null;
  const p = safe.period;
  const statements = [
    env.DB.prepare(
      `INSERT INTO telemetry_periods
         (period, batch_count, last_received_at${cohortColumn ? `, ${cohortColumn}` : ""})
       VALUES (?, 1, ?${cohortColumn ? ", 1" : ""})
       ON CONFLICT(period) DO UPDATE SET
         batch_count = batch_count + 1,
         last_received_at = excluded.last_received_at${
           cohortColumn ? `, ${cohortColumn} = ${cohortColumn} + 1` : ""}`
    ).bind(p, receivedAt),
    upsertDimension(env, p, "version", safe.app.version),
  ];
  if (country) statements.push(upsertDimension(env, p, "country", country));
  for (const source of safe.sources) statements.push(upsertDimension(env, p, "source", source));
  for (const kind of safe.destinations) statements.push(upsertDimension(env, p, "destination", kind));
  if (safe.backend) statements.push(upsertDimension(env, p, "backend", safe.backend));
  if (safe.scale.links) statements.push(upsertDimension(env, p, "links", safe.scale.links));
  if (safe.scale.themes) statements.push(upsertDimension(env, p, "themes", safe.scale.themes));
  for (const kind of safe.feed_kinds) statements.push(upsertDimension(env, p, "feed_kind", kind));
  for (const id of safe.known_feeds) statements.push(upsertDimension(env, p, "known_feed", id));
  for (const [feature, on] of Object.entries(safe.features)) {
    statements.push(upsertDimension(env, p, "feature", feature, on ? 1 : 0));
  }
  await env.DB.batch(statements);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/v1/community") {
      return json(await communityStats(env), 200, {
        "access-control-allow-origin": "*",
        "cache-control": "public, max-age=300",
      });
    }
    if (request.method === "GET" && url.pathname === "/v1/feeds/known") {
      return json({ version: KNOWN_FEEDS_VERSION, feeds: KNOWN_FEEDS }, 200, {
        "access-control-allow-origin": "*",
        "cache-control": "public, max-age=3600",
      });
    }
    if (request.method === "GET" && (url.pathname === "/" || url.pathname === "/community")) {
      return new Response(communityPage(), {
        headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" },
      });
    }
    if (request.method !== "POST" || url.pathname !== "/v1/batches") {
      return json({ error: "not_found" }, 404);
    }
    if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
      return json({ error: "content_type_required" }, 415);
    }
    let payload;
    try {
      payload = await request.json();
    } catch {
      return json({ error: "invalid_json" }, 400);
    }
    const safe = sanitize(payload);
    if (!safe) return json({ error: "invalid_payload" }, 400);
    const receivedAt = new Date().toISOString();
    const country = requestCountry(request);
    const result = await env.DB.prepare(
      `INSERT OR IGNORE INTO telemetry_batches
       (batch_id, received_at, period, dedupe_key, app_version, macos_major, architecture, country, payload)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(
      safe.batch_id, receivedAt, safe.period, safe.dedupe_key, safe.app.version,
      safe.app.macos_major, safe.app.architecture, country, JSON.stringify(safe),
    ).run();
    const inserted = (result.meta?.changes ?? result.changes ?? 0) > 0;
    if (inserted) await recordRollups(env, safe, receivedAt, country);
    return json({ ok: true });
  },

  /** Raw batches and per-week breakdowns expire; weekly counts stay. */
  async scheduled(_event, env) {
    const expired = await env.DB.prepare(
      `SELECT period FROM telemetry_periods WHERE last_received_at < datetime('now', ?)`
    ).bind(`-${COMMUNITY_WINDOW_DAYS} days`).all();
    const periods = (expired.results ?? []).map((row) => row.period);
    if (periods.length > 0) {
      await env.DB.prepare(
        `DELETE FROM telemetry_dimensions WHERE period IN (${periods.map(() => "?").join(",")})`
      ).bind(...periods).run();
    }
    await env.DB.prepare(
      "DELETE FROM telemetry_batches WHERE received_at < datetime('now', ?)"
    ).bind(`-${COMMUNITY_WINDOW_DAYS} days`).run();
  },
};
