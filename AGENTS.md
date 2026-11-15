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
transcripts), not only the link. Never add a Sift account, and never send
library content (links, titles, text, theme names, notes) to any Sift server.
The one exception is anonymous diagnostics (owner, 2026-11-15, below).

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
- Chrome tabs (issue #1): `ChromeExtension/` (MV3, plain JS, permissions
  `tabs` + `nativeMessaging` only) talks to `sift-chrome` (target in
  project.yml, `SiftChrome/main.swift`, embedded in Contents/MacOS, signed
  in build-app.sh, checked in release.yml) over Chrome native messaging
  (4-byte little-endian length + JSON). The extension keeps a port open, so
  its worker lives and resends every minute; the host writes
  `Application Support/Sift/chrome/tabs-<install>.json` only when tabs
  change (or hourly) and answers with the URLs in `chrome/close.json` open
  in that profile. `ChromeReader` makes each file a source
  `chrome:<install>`; the install id is a random UUID the extension keeps
  in IndexedDB. Extensions cannot read the profile name, so the user names
  profiles in Settings (`chromeProfileNames`). The close queue routes by
  URL: open in Chrome goes to close.json, the rest to close.txt.
  Extension id `olgmdjbjikcjaohhpmeekcmiknpfofpb` comes from the public
  `key` in manifest.json (private key discarded; `ChromeHelper.extensionID`
  must match). `ChromeHelper.install` writes `app.sift.chrome.json` into
  each Chromium browser's NativeMessagingHosts folder. Not in the Web Store.
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
- Background library jobs (2026-11-14): `startLibraryJobs()` runs on
  reload and every 15 minutes. A refusal (YouTube IP block, Instagram rate
  limit) sets `state.blockedUntil[job]` with a doubling wait (1 h to 24 h)
  that survives relaunches; never retry a blocked service on launch. Speech
  recognition has a deadline (3x the audio length, at least 90 s) so one
  silent reel cannot stall the queue. Pass "--" before a YouTube id: ids
  can start with "-".
- YouTube metadata (2026-11-14): titles and channel from YouTube's public
  oEmbed (`PreviewFetcher.youTube`, 1 request a second, job
  `fetchVideoTitles`); length (`lengthSeconds`) and description from the
  watch page at capture (`Library.Entry.duration`, front matter
  `duration:`), which also refreshes the preview. Videos captured without a
  length are read again once, unless a transcript is in the file.
- Sidebar: Overview is the graph; a source or theme picked in the sidebar
  opens its list (a theme picked on the graph keeps the graph panel).
- Data safety (2026-11-14): state.json, archive.json, previews.json and
  Library/index.json load and save through `SafeStore`: hourly backups in
  `Application Support/Sift/Backups` (24 per file); an unreadable file is
  copied aside and the newest readable backup is used; with none, saving
  that file is off for the run. A save that shrinks a file over 64 KB to
  under a tenth is refused. Problems show in an alert. Never write these
  files directly.
- YouTube audio route (2026-11-14, owner: "make it clean"): when YouTube
  refuses captions (job "youtube" blocked), `AppModel.hear` fetches the
  audio with yt-dlp (`-f ba[ext=m4a]`, gate "audio.youtube.com", own block
  key "youtube-audio") and transcribes it on device only
  (`onDeviceOnly`), skipping videos over 90 minutes; the file heading says
  "from the audio". Switch: `state.youtubeAudio`.
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
- Theme memory (2026-11-14): `Project.history` (dated lines) and
  `continues` from discovery so history follows a renamed or merged theme.
  The notes field was removed from the UI at the owner's request;
  `Project.notes` still decodes and still reaches prompts if set.
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
  (sent Safari tabs go on the close list). Starlings is one destination
  per workspace, "Starlings: <name>" (the `name` in the workspace's
  `/.well-known/meet`), saving private link saves; no projects (owner's
  call, 2026-11-14; old project destinations are removed on launch).
  Starlings: OAuth 2.1 with
  dynamic registration, PKCE, loopback 127.0.0.1:53683, `resource`
  <origin>/mcp, tokens per workspace in the keychain
  (`app.sift.starlings.<host>`); `docs_write` with `url` + project subject
  + idempotency key is a link save. Old `Assignment.action` data still
  decodes but nothing reads it.
- Links show only as rows (`TabCard`); the card grid was removed at the
  owner's request (2026-11-14). Lists take arrow keys and space (browser).
  A focused theme in the graph opens a left panel and keeps the cluster in
  view. The settings tab for Claude, the on-device model and MCP is named
  Intelligence.
- Cluster layout (2026-11-14): no site twigs. Leaves spiral out by recency
  (newest nearest the hub). Solid dot = text or transcript saved; ring =
  title only.
- Graph focus selects the theme in the sidebar (`AppModel.graphTheme`);
  Overview or a source in the sidebar zooms back out.
  link feeds two themes or destinations). Not built.

- Setup Guide (2026-11-14): `Sift/Onboarding/`, one file per step,
  conforming to `OnboardingStep`, registered in `Onboarding.steps`. It is a
  single `Window` scene (id `setup-guide`), not a sheet, so it works with
  several main windows or none and can present ThemeReview itself.
  `state.onboardingSeen` lists the step ids shown; a new id shows once as
  "New in Sift". nil means the state predates the guide: an install with
  themes or assignments counts as seen. Set it to `[]` to see the first run
  again. Source status lives in `Views/SourceStatus.swift`, shared with
  Settings > Inputs. A missing tab database (no Full Disk Access) no longer
  blocks the window: the other sources load and a banner points to the guide.

- AppModel is split by area (2026-11-14, refactor only). `App/AppModel.swift` holds the class, every
  stored property (grouped by area), `init` and `reload()`. Extensions: `+Sources` (source selection,
  sites), `+X`, `+Archive` (Instagram Saved, archive), `+Library` (capture, YouTube and reel
  transcripts, library jobs and backoff, Instagram images), `+Imports`, `+Send`, `+Themes` (projects,
  themes, sorting, connections), `+Upkeep` (duplicates, notes, saved searches, search, previews),
  `+Closing` (Chrome and iPhone close lists), `+Export` (exporters, CSV import, `CSV`),
  `+LocalModel`. New stored properties go in the class body, never in an extension.
- Demo mode (2026-11-14): launch argument `-demo` or `SIFT_DEMO=1`
  (`Sift/Demo/Demo.swift`). `StateFile.url` (and so every Sift data path:
  library, images, imports, backups, search index, chrome, tools), Safari's
  CloudTabs.db, the Reading List plist and the iPhone close list point into
  `Application Support/Sift-Demo`, which is replaced on each launch from the
  bundle's `Demo/` folder (`{{DEMO_PATH}}` and `{{DEMO_URL}}` in its JSON are
  filled in). Off in demo mode: previews, capture, transcripts, reel and
  YouTube jobs, Instagram images, Claude, the on-device model, Starlings, X,
  the Chrome helper, Add to Reading List, the web pane and the keychain
  (reads empty); a `URLProtocol` fails every http(s) request on
  URLSession.shared as a backstop. Send records a sent link and calls no
  sender. The Setup Guide does not open. `-demoView graph | theme:<name> |
  list:<source> | settings:<tab>`, `-demoSize WxH` and `-demoAppearance
  light|dark` serve `scripts/screenshots.sh`. Sample data: edit
  `scripts/demo/content.py`, run `python3 scripts/demo/make-data.py`, commit
  `Demo/`. Every new data path must derive from `StateFile.url`, and every
  new network or account call needs a `Demo.isOn` guard. Never take README
  screenshots from real data. sift-mcp and sift-chrome do not know demo
  mode and still read the real Sift folder.

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

- Anonymous diagnostics (2026-11-15, owner's call: on by default, own
  Worker). Ported from Headroom. Client: `Sift/Telemetry/Telemetry.swift`
  (`TelemetryCoordinator`, started in `AppModel.init`, checks 60 s after
  launch and every 6 h, at most one batch per ISO week, a failed send is
  kept in `telemetry/pending.json`). Worker and D1: `telemetry/`
  (`sift-telemetry`, https://sift-telemetry.envisioning.workers.dev,
  `/v1/batches`, `/v1/community`, `/community`). Contract:
  `docs/telemetry.md`. No install id: a week-scoped HMAC of a local secret
  (keychain `app.sift.telemetry` + `telemetry/install_secret`) dedupes, and
  the Mac sends its own cohort word. Off in demo mode. Settings > Privacy
  has the switch and shows the batch. A new field needs three changes in
  step: `TelemetryBatch`, the Worker's whitelist, and docs/telemetry.md.
  Never add a field that carries library content or an identifier.
  `wrangler d1 execute --remote` needs `--yes`, and a migration goes in
  before the Worker that reads it.
