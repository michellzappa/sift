# Sift telemetry service

The intake for Sift's anonymous weekly report and the public Community
Pulse page. Ported from Headroom's. One Worker, one D1 database, no
accounts and no client credential. The privacy contract is
[docs/telemetry.md](../docs/telemetry.md); the client is
`Sift/Telemetry/Telemetry.swift`.

Live at https://sift-telemetry.envisioning.workers.dev:

- `POST /v1/batches`: one report (schema 1)
- `GET /v1/community`: public totals (JSON)
- `GET /community`: the Community Pulse page

## Deploy

```bash
pnpm dlx wrangler deploy
```

Schema changes: write the SQL, apply it before deploying the Worker that
reads it, and check the columns rather than the exit code:

```bash
pnpm dlx wrangler d1 execute sift-telemetry --remote --yes --file=schema.sql
pnpm dlx wrangler d1 execute sift-telemetry --remote --json --command="SELECT name FROM sqlite_master WHERE type='table';"
```

`--yes` matters: piped through `tail` or `grep`, wrangler answers its own
prompt with no and still exits 0.

A cron runs daily at 03:17 UTC and deletes raw reports and breakdowns
older than 180 days. Weekly counts stay.
