# Anonymous usage counts

Sift keeps your library on your Mac. The one thing it sends to its makers
is a small weekly report, so we can see which versions, Macs and features
are in use. It is on by default. **Settings > Privacy** turns it off and
shows the exact report it would send. Turning it off deletes any report
waiting to go out. Demo mode never sends one.

The design comes from Headroom's diagnostics and works the same way.

## What is sent

At most one report per Mac per ISO week:

- app version and build, macOS major version, CPU family (`arm64` or
  `x86_64`);
- the kinds of source that have links: `safari`, `chrome`, `reading-list`,
  `instagram`, `x`, `import`;
- the kinds of Send destination you set up: `starlings`, `obsidian`,
  `markdown`, `reading-list`;
- the sorting backend: `claude-code` or `api`;
- rough sizes: saved links (`0`, `1-99`, `100-999`, `1000-9999`, `10000+`)
  and themes (`0`, `1-4`, `5-9`, `10-19`, `20+`);
- switches: themes exist, on-device model available, on-device first pass,
  on-device summaries, YouTube transcript tool installed, reel transcript
  tool installed, YouTube audio route, connections, close after send;
- a week key, `HMAC-SHA256(install secret, ISO week)`, so a second report
  from the same Mac in the same week is ignored;
- one cohort word: `new`, `returning` or `reactivated`.

## What is never sent

Links, URLs, page titles, page text, transcripts, theme names, notes,
device names, Chrome profile names, import names, file paths, Starlings
workspaces, accounts, keys or tokens. There is no install id, hardware id
or serial number.

The install secret stays on the Mac, in the login keychain (service
`app.sift.telemetry`) and in `~/Library/Application Support/Sift/telemetry/install_secret`.
Only the week key leaves, and it changes every week, so the server cannot
join one week's report to the next. The random `batch_id` only lets the
server ignore a retried request.

## Retention without an install id

The Mac compares the week it reports with the last week it reported, and
sends one word:

| Cohort | Meaning |
|---|---|
| `new` | this Mac never reported before |
| `returning` | it reported last week |
| `reactivated` | it reported before, but not last week |

The server learns that some Mac came back, never which one. A Mac that
turns the switch on after a while reports `new`.

## On the server

The Worker in `telemetry/` checks every field against a fixed list and
drops anything else. It does not store request headers or IP addresses.
It stores the country code from Cloudflare's edge, never the IP.

- Raw reports and per-week breakdowns are deleted after 180 days.
- Weekly counts (a week, a number of Macs, the cohort split) are kept, so
  the growth chart can show more than six months.

## Community Pulse

The totals are public at
https://sift-telemetry.envisioning.workers.dev/community, with the JSON at
`/v1/community`. The newest week is always still filling: a Mac reports at
its first launch in a week. The page and the Worker are open in
`telemetry/`, so anyone can check them or run their own.
