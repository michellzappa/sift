# Sift — agent notes

Sift builds a local knowledge model of a person's interests from what they
already save on the platforms they use: Safari tabs, Reading List, Instagram,
X, YouTube, imports. It keeps the full text (pages, transcripts) on the Mac in
open formats, finds the themes with the user's own Claude, and sends links on
to where they are used (Starlings, Obsidian, files).

North star (owner, 2026-11-14): the user owns their data. Everything Sift
learns stays on the Mac as plain files (Markdown library, JSON state, SQLite
index), readable without Sift, and reachable by the user's own Claude through
sift-mcp. New inputs are judged by how much of the content they keep (text,
transcripts), not only the link. Never add a Sift server or account.

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
- Instagram Saved: `InstagramReader`, source id `instagram-saved`. Reads
  `your_instagram_activity/saved/saved_posts.json` and
  `saved_collections.json` from the JSON data export the user picks in
  Settings (`instagramExportPath`): the zip through `/usr/bin/unzip -p`, or
  the unpacked folder. Instagram writes UTF-8 as one `\u00XX` escape per
  byte; `InstagramReader.fix` turns it back into text. Never commit
  anything from an export.
- State: one JSON file, `~/Library/Application Support/Sift/state.json`,
  keyed by URL. Hand moves set `manual: true`; the sorter never overwrites them.
- API key: login keychain, service `app.sift.anthropic-api-key`.

## Decisions

- Themes are the only categories, always generated (2026-11-14). There is
  no repo scanning and no fixed project list. `Sorter.discoverThemes`
  clusters the whole corpus (phone tabs + Reading List + Instagram Saved) in one Claude call
  through the user's own backend. Themes are `Project` with `isTheme`;
  non-theme entries are hand-added destinations, used only as hints. A rerun
  passes the current themes as names to keep, so links do not reshuffle. The
  user accepts every proposal in `ThemeReview`. Sorting is disabled until
  themes exist.
- Transactional tabs go to the `errands` bucket (`Sorting/Errands.swift`,
  URL rules; Claude's "errand" kind for the rest). They are excluded from
  theme discovery input, themes, the graph and exports. Hand moves win.
- Engine step 1, capture (2026-11-14): `Sift/Engine/Capture.swift`.
  `Capturer` fetches each archived link once (4 at a time) and `Readable`
  extracts the main text with regular expressions (no dependencies); PDFs
  via PDFKit; X posts from the text Sift has. `Library` writes one Markdown
  file per link (front matter + text) and `index.json`. Next steps: digests
  by the user's Claude, theme memory, local search (SQLite FTS5).
- YouTube transcripts (2026-11-14, owner's choice of the free route):
  `Engine/Transcripts.swift` calls the optional `youtube-transcript-api`
  CLI (installed into `Application Support/Sift/tools/venv`), paced through
  `HostGate` ("transcripts.youtube.com", 4 s), pausing an hour on throttling.
  Transcripts are appended to the library file under "## Transcript".
- Reel transcripts (2026-11-14, owner's choice): `Engine/ReelTranscripts.swift`.
  The optional `yt-dlp` (same venv as the YouTube tool) fetches the audio
  track (`-f ba/b`) without a login, through `HostGate` key
  "reels.instagram.com"; it pauses an hour on rate-limit or login-required.
  `SFSpeechRecognizer` (on-device when supported; locale from the caption
  language) makes the text; the audio is deleted. Appended under
  "## Transcript". Never pass browser cookies to yt-dlp: it risks the
  owner's Instagram account.
- Capture paces requests per site (`HostGate`: 4 s for YouTube, Instagram
  and X, 1 s elsewhere) and skips a site for an hour after 429/503. Never
  fetch one site in parallel bursts: YouTube rate-limited the owner's IP.
- Exporters are plugins: one file per exporter in `Sift/Export/`, conforming
  to `Exporter`, registered in `Exporters.all`. They read only the
  `ExportSnapshot`: no network, keychain or app state. CONTRIBUTING.md is the
  checklist.
- Search (2026-11-14): `Engine/SearchIndex.swift` rebuilds
  `Application Support/Sift/search.sqlite` (FTS5 over titles, page text,
  transcripts, previews; tables links, fts, themes, meta) 3 s after library,
  archive or theme changes, into a temp file swapped in. The filter in every
  list matches it. `SiftMCP/` is a stdio MCP server (`sift-mcp`, embedded in
  Contents/MacOS) that reads the same file read-only: tools search,
  get_link, list_themes, theme_links. Keep both schemas in step.
  `scripts/build-app.sh` signs sift-mcp before the app.
- Theme memory (2026-11-14): `Project.notes` (the user's words, sent to
  Claude when sorting and rediscovering) and `Project.history` (dated lines).
  Discovery returns `continues` so notes follow a renamed or merged theme.
- Connections (2026-11-14): `Sorter.connections` asks, 60 links at a time,
  which other themes a link feeds (`Assignment.also`, max 2; nil = not
  checked). The graph weighs shared links 3x a shared site and draws a dashed
  line from such a link to the other hub. New themes reset `also`.
- Raindrop-style upkeep (2026-11-14): `URLKey.normalize` (tracking
  parameters, www/m., twitter.com, youtu.be) finds duplicates; Merge All
  writes `state.mergedInto` and hides merged links while the kept one is
  present. Capture marks 404/410/no-such-host as status "gone" (Broken
  Links). Notes per link live in `ArchiveRecord.takeaway` and go into the
  search index. Saved searches (`state.savedSearches`) list FTS hits.
- Send replaced next actions (2026-11-14, owner's call; filing is
  immediate, no confirm step). `Sift/Send/`: `Sender` plugins (Starlings,
  Obsidian, Markdown, Reading List), `state.destinations`, `state.sent`
  (url → records), `Project.sendTo` (theme default), `closeAfterSend`
  (sent Safari tabs go on the close list). Starlings: OAuth 2.1 with
  dynamic registration, PKCE, loopback 127.0.0.1:53683, `resource`
  <origin>/mcp, tokens per workspace in the keychain
  (`app.sift.starlings.<host>`); `docs_write` with `url` + project subject
  + idempotency key is a link save. Old `Assignment.action` data still
  decodes but nothing reads it.
- Links show as rows by default (`LinkStyle`, `@AppStorage("links.style")`,
  `LinkStyleToggle`); cards are the grid option. `TabCard` draws both and
  shares menus. Lists take arrow keys and space (browser). In the graph,
  the list layout opens a left panel and keeps the cluster in view.
- Cluster layout (2026-11-14): no site twigs. Leaves spiral out by recency
  (newest nearest the hub). Solid dot = text or transcript saved; ring =
  title only.
- Graph focus selects the theme in the sidebar (`AppModel.graphTheme`);
  Overview or a source in the sidebar zooms back out.
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
- On-device model (2026-11-14, issues 5, 6, 7): `Engine/LocalModel.swift`
  wraps Apple's Foundation Models (macOS 26+, Apple Intelligence on), behind
  `#available` and `SystemLanguageModel.default.availability`; the framework
  is weak-linked in project.yml so the app still runs on macOS 14. In
  `sortUnsorted`, `AppModel.sortOnDevice` runs first: a sure errand or noise
  verdict (`@Generable` enums) goes to errands or drop, then a sure pick from
  the current themes (`DynamicGenerationSchema` enum of names + "none") goes
  into that theme. Everything else goes to Claude. `Assignment.sortedBy` is
  "device" or "claude" and survives a hand move, for audits. Summaries run
  after capture, one at a time, newest first, not on battery, in chunks of
  6,000 characters (the macOS 26 SDK has no context size API; the window is
  4,096 tokens). They live in `Library.Entry.summary`, the file's `summary:`
  front matter and `links.summary`, which sift-mcp shows. Theme discovery
  and connections stay on Claude. Switches: `localFirstPass`,
  `localSorting`, `localSummaries` (on by default).
