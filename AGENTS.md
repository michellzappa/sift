# Sift — agent notes

Sift is a native macOS app that turns open Safari tabs into project material.
It reads the iCloud Tabs database that Safari syncs to this Mac, sorts each tab
into one of the user's projects with Claude, and shows the result as a list per
project and as an overview network (one hub per project, one dot per tab).

## Commands

- Gate: `remote-build 'xcodegen generate -q && xcodebuild -project Sift.xcodeproj -scheme Sift -configuration Debug -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build'`
- Install on the laptop: `./scripts/build-app.sh` (signs and copies to /Applications).
- XcodeGen is the source of truth. `Sift.xcodeproj` is generated and ignored.

## How it works

- Tabs: `~/Library/Containers/com.apple.Safari/Data/Library/Safari/CloudTabs.db`,
  tables `cloud_tabs` and `cloud_tab_devices`. Opened read-only. Sift never
  writes to it. `last_viewed_time` is seconds since 2001-01-01.
- Reading it needs Full Disk Access. TCC keys the grant to the code signature,
  so the app is signed with the Apple Development identity, never ad-hoc.
- Projects: git repos up to two levels under the projects folder (default
  `~/Dev`), with a summary from README.md or AGENTS.md. The user can add
  projects with no repo and hide repos.
- Sorting: `Sorter`, batches of 40, one prompt and one JSON schema (project
  enum), two backends. Default `claude -p` (`ClaudeCodeRunner`) with the
  user's Claude Code login: `--json-schema`, answer in `structured_output`.
  Tools, MCP, skills, settings and the default system prompt are off, so a
  call costs about 1.5k input tokens instead of about 140k. Never use
  `--bare`: it skips the stored login ("Not logged in"). Fallback: Messages
  API over HTTP (`APIRunner`, `claude-opus-5-5`, effort `low`, server-side
  fallback). Both send title, URL and preview text, never page bodies.
- Previews: `PreviewFetcher`. X posts use the public oEmbed endpoint
  (publish.twitter.com/oembed), which returns post text without a login, or
  the opt-in syndication endpoint (see Decisions).
  Other pages use Open Graph tags from the HTML. Cache:
  `~/Library/Application Support/Sift/previews.json`.
- Closing tabs: a Mac cannot close tabs on another device. Sift writes the
  close list to iCloud Drive/Sift/close.txt; an iPhone Shortcut (Find Tabs,
  Close Tab) closes them. Reload prunes URLs that are no longer open.
  Safari's own `cloud_tab_close_requests` table is not used: its rows carry
  CloudKit system fields that Sift cannot make.
- State: one JSON file, `~/Library/Application Support/Sift/state.json`,
  keyed by URL. Hand moves set `manual: true`; the sorter never overwrites them.
- API key: login keychain, service `app.sift.anthropic-api-key`.

## Decisions

- Themes are bottom-up (2026-11-14). `Sorter.discoverThemes` clusters the
  whole corpus (phone tabs + Reading List) in one Claude call through the
  user's own backend. Themes are stored as `Project` with `isTheme`; when any
  exist, `AppModel.projects` returns only themes and repos become
  `destinations`. A rerun passes the current themes as names to keep, so
  links do not reshuffle. The user accepts every proposal in `ThemeReview`.
- Next direction: a graph view (themes as hubs, links as nodes, edges where a
  link feeds two themes or destinations). Not built.

- No HouseKit code dependency: Sift is a window app, not a menu-bar app, and
  uses the SwiftUI Settings scene. The icon is the HouseKit `sift` glyph;
  `scripts/build-app.sh` regenerates `AppIcon.icns` from `../../housekit`.
- `*.csv` is ignored so exported tab lists (browsing data) never get committed.
- X previews use oEmbed by default. An optional setting (`xSyndication`, off
  by default) asks X's syndication endpoint
  (cdn.syndication.twimg.com/tweet-result) first, for post images and the
  author avatar. It is unofficial and can break; oEmbed is the fallback.
  Added 2026-11-14 at the owner's request. The paid X API, crawler user
  agents and third-party preview services are not used.
