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

- HouseKit (2026-11-15, owner): Sift depends on HouseKit for the settings
  shell (`HouseSettingsView`, `SettingsPane`, `GeneralSettingsPane`,
  `AboutSettingsPane`, `UpdatesSection` through `UpdateChecker:
  UpdateChecking`) and the changelog (`Changelog`, `ChangelogView`). It is a
  URL package pinned to a commit in project.yml, so CI and the mini resolve
  it without a sibling checkout; move the pin on purpose. The icon is
  Sift's own (owner, 2026-11-15: a card deck, not the HouseKit glyph):
  `scripts/icon/make-icon.swift` writes `Sift/Resources/AppIcon.icns` and
  the phone's `App/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (full
  bleed, no alpha). Both are committed; run the script after a change.
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
  the Mac sends its own cohort word. Off in demo mode. Settings > Telemetry
  has the switch, shows the batch and, while on, the Community Pulse
  (`Telemetry/CommunityPulse.swift`, reads `/v1/community`, Headroom's
  layout). A new Pulse field: Worker `communityStats` and `CommunityStats`. A new field needs three changes in
  step: `TelemetryBatch`, the Worker's whitelist, and docs/telemetry.md.
  Never add a field that carries library content or an identifier.
  `wrangler d1 execute --remote` needs `--yes`, and a migration goes in
  before the Worker that reads it. Feeds (issue #33, owner: on by
  default): `feed_kinds` (provider ids) and `known_feeds` (ids from the
  Worker's public list `telemetry/known_feeds.js`, served at
  `/v1/feeds/known`, matched on the Mac; own switch `telemetryKnownFeeds`;
  Pulse floor 5). Never report a feed that is not on that list. Add only
  large public feeds to it; never rename an id.

- Updates (2026-11-15, ported from Headroom's updater, owner's request).
  `Sift/App/Updates.swift`: `UpdateChecker` asks GitHub's
  `releases/latest` for michellzappa/sift once a day (first check 60 s
  after launch; off in demo mode and for copies outside /Applications),
  shows "Update to X" in the toolbar and in Settings > General, and
  File-menu "Check for Updates…" in the app menu. The install is
  `scripts/update-app.sh`, shipped in Contents/Resources (project.yml;
  release.yml fails without it), run detached with `--yes --version X`,
  log in `Application Support/Sift/logs/update.log`. Before it touches
  anything it checks SHA256SUMS, `spctl`, `codesign --deep --strict`, team
  992N457T8D (compiled into the script, never read from the release) and
  that the bundle version equals the tag; then it quits Sift, keeps the old
  bundle until `ditto` succeeds, strips quarantine and opens Sift. No
  Sparkle. The zip name `Sift-<version>.zip` and `SHA256SUMS` are part of
  the contract: release.yml and the script must agree.
- Transcripts (2026-11-15): sidebar "Transcripts" lists links whose
  library entry has `transcript == true`. The web pane opens such a link on
  its transcript (reader view); the toggle switches to the video. The pane
  stops media (`WebPage.stop`) when it closes or switches to the reader.
- Rows carry no icon buttons (owner, 2026-11-15): Send is in the context
  menu and the web pane header, not on the row.


- Progress (2026-11-15, owner): one list, `AppModel.activities`
  (`App/Activity.swift`), built from the job flags and `state.blockedUntil`.
  The sidebar footer (`LibraryStatus`) shows every running or paused job,
  label and count above the bar. The banner above the list shows decisions
  only (unsorted links, no themes) and hides while sorting or discovery
  runs. A new background job adds its row to `activities`, never its own bar.
- Changelog (2026-11-15, Headroom's logic, now HouseKit's): `CHANGELOG.md`
  is the one source. Add `## X.Y.Z - YYYY-MM-DD` with `### Added/Changed/
  Fixed` before tagging; release.yml fails without it
  (`scripts/changelog-section.sh`) and uses the section as the GitHub
  release notes. The file ships in Resources: Sift > Version History…
  (Window `version-history`) and Settings > About show it.
- Settings layout (2026-11-15, owner): the HouseKit shell, panes General,
  Inputs, Library, Outputs, Intelligence, Themes, Telemetry, About (ids are
  the lowercase names; `-demoView settings:<id>`). A new pane is one more
  `SettingsPane` in `SettingsView.panes`.
- Seen and unseen (2026-11-15, owner: "swipe = seen", email-style).
  `Storage/Seen.swift` + `App/AppModel+Seen.swift`. Each device writes only
  its own file, `iCloud Drive/Sift/seen/<mac|iphone>-<id>.json` (URL →
  `{seen, at}`); every device reads all of them and the newest mark per URL
  wins. No server, no shared file, so iCloud never sees a write conflict.
  A link is unseen until opened (web pane) or marked. Sidebar theme counts
  are unseen counts; lists have Unseen Only and Mark All as Seen. Loaded on
  launch, with each library round and when Sift becomes active. Not yet in
  search.sqlite or sift-mcp. The iOS prototype (`prototypes/ios-deck`) uses
  the same files: a card on screen for a second counts as seen when you
  swipe on.
- Feeds (2026-11-15, owner: "feeds now, TikTok next"; feeds are a power-user
  input, the mainstream input is what people save on Instagram, TikTok and
  X). `Engine/Feeds.swift`: `Feed` (in `state.feeds`), `FeedEntry`,
  `FeedStore` (items per feed in `Application Support/Sift/feeds/<id>.json`,
  90 days or the newest 20 at any age, 150 per feed), `FeedParser` (RSS 2.0, RDF, Atom, JSON Feed, OPML
  in and out; XMLParser, no dependencies), `FeedFetcher` (conditional GET
  with ETag/Last-Modified, paced by `HostGate`, an hour's pause on 429/503;
  `discover` reads `<link rel="alternate">`, then common paths).
  `AppModel+Feeds.swift`: one source, `FeedStore.sourceID` ("feeds"); feed
  text and images fill `previews`; `fetchFeeds` runs with the library jobs
  for feeds older than an hour. Settings > Inputs > Feeds
  (`Views/FeedSettings.swift`): Import OPML with folder and per-feed
  checkboxes (all picked at first), Add Feed by address, Check Now, Export
  OPML. Telemetry source kind `feed` (client, Worker whitelist, docs).
- Saved vs offered, Today (2026-11-15, owner; issues #27, #30). Saved
  items (tabs, Reading List, Instagram, X bookmarks, imports, kept items)
  are sources, themes, library. Offered items (feeds now; Bluesky,
  Mastodon, X people later) are never sources or themes: they show only in
  Today. `Engine/Today.swift`: `TodayBuilder` ranks items from the last 3
  days, locally (freshness, keeps per feed, theme word overlap, the same
  normalized URL in several feeds), at most 3 unseen per feed, one
  wildcard, a reason line per pick; no Claude call. Rolling (owner,
  2026-11-15: "can update, not show just 10"): no total cap and no 07:00 /
  17:00 slots. `refreshToday` merges after each feed check, follow and
  Today visit: picks already there keep their place (seen ones until they
  leave the window, `stillCurrent`), new picks go on top in rank order
  (`merge`, one unseen wildcard at a time). `force` (Rebuild Today, a
  priority change) builds from nothing. `TodayDigest.slot` now holds the
  build time.
  `state.today` (`TodayDigest`, picks carry their own title, summary,
  image) and `state.kept` (`KeptItem`). `AppModel+Today.swift`: Keep moves
  an item into the saved source `kept` ("Kept from Today"), marks it seen
  and reloads; `refreshToday` runs with the library jobs and after a feed
  check. `Views/TodayView.swift`: sidebar Today (open count), rows with no
  icon buttons; K, the context menu or Keep above the page keeps. A
  one-time `pruneOfferedFromArchive` removes 0.7.0 feed items from the
  archive unless kept, sent or noted. Next: the phone's Today and Library
  tabs (#30), YouTube subscriptions from Takeout as feeds, Bluesky (#23).
- Today on the phone (2026-11-15, owner: "two tabs"). The Mac writes
  `iCloud Drive/Sift/Deck/today.json` (`writeTodayForPhone`: slot, next,
  picks, kept URLs) whenever the digest or kept list changes. The phone
  writes its keeps to `kept/iphone-<id>.json` (`[KeptItem]`, ISO 8601);
  `mergeDeviceKept` (run from `loadSeen`) adds new ones to `state.kept`
  and marks them seen. Prototype tabs: Today (swipe = seen, double-tap =
  keep, tap = open; video opens the reader with the player), Library (Deck
  or Deeper), Lists, Log.
- Subscribe links (2026-11-15): Info.plist registers `feed`, `feeds` and
  `sift`; `SiftApp` `.onOpenURL` calls `AppModel.subscribe(from:)`, which
  maps feed://, feed:https:// and sift://subscribe?url= to an address, runs
  `FeedFetcher.discover` and follows the feed.
- RSS is the primary input (2026-11-15, owner: "FOCUS on rss … plugin style
  extension for new rss sources"). Feed providers are plugins:
  `Sift/Feeds/FeedProvider.swift` (`FeedProvider`: `id`, `name`, `symbol`,
  `examples`, `matches` with no network, `candidates` may use the network;
  `FeedProviders.all`, `WebProvider` last; `resolve` fetches and parses each
  candidate, then falls back to web discovery). One file per provider in
  `Sift/Feeds/Providers/`: Reddit, YouTube (channel id from the page),
  Substack, Bluesky (one @ and a dot), Mastodon (@user@instance,
  #tag@instance), Medium, Tumblr, GitHub (releases and commits), Podcast
  (iTunes lookup and search), Hacker News (hnrss.org for queries), Google
  News search, arXiv, Web. `Feed.provider` keeps the id for the icon; OPML
  feeds get one from the host (`AppModel.providerID(forFeed:)`). Follow
  sheet `Views/AddFeedSheet.swift` (toolbar +, Shift-Command-N, Settings,
  `model.showAddFeed`). Sidebar Feeds section: folders (`.feedFolder`) and
  feeds (`.feed`) open `FeedItemsView`, which shares `OfferedList` with
  Today; no unread counts (owner's no-pile rule). With feeds, the start
  view is Today. CONTRIBUTING.md has the provider checklist.
- Version numbers (owner, 2026-11-15): odometer style. Each part of X.Y.Z
  runs 0 to 9: after x.y.9 comes x.(y+1).0, after x.9.z comes (x+1).0.0.
  Never a two-digit part (0.10.0 was re-cut as 1.0.0).
- Following from anywhere (2026-11-15, owner: "make it easy to add new
  feeds via ux/ia"). `FeedFetcher.discover` asks the matching provider's
  pattern rules first (Reddit .rss, GitHub releases.atom, YouTube, Medium,
  Tumblr…), so every caller gets them. `Feeds/FeedSuggestions.swift`:
  hosts saved 3+ times (platforms without feeds skipped), subreddits and
  GitHub repos saved 2+ times, not followed; local only, shown in the Follow
  sheet with evidence. `AppModel.followInput(forLink:)` maps a link to what
  Follow takes (r/name, owner/repo, a YouTube page, a profile, else the
  host); `followQuick` follows the first result without the sheet. Entry
  points: Follow sheet, File > Follow… (Shift-Command-N), toolbar +, the
  sidebar Feeds section (always shown, Follow row, drop a link), "Follow
  <site>" in every row's context menu, the button above the open page.
- Sidebar chapters (2026-11-15, owner): "Feeds" (Today, folders, feeds,
  Follow row; drop target) and "Library" (Overview, sources, Unsorted,
  Archive, Transcripts, Duplicates, Broken Links, To Close), then Saved
  searches, Themes, Sent to, Sites. Each section folds (`sidebar.*` in
  AppStorage).
- Feed full text (2026-11-15, owner: "showing all available text …
  respecting linebreaks … formatting if we have MD"). `FeedEntry.content`
  and `TodayPick.content`: the item as Markdown (`FeedParser.Text.markdown`,
  regex HTML to Markdown: paragraphs, br, h1-h4 demoted one level, strong,
  em, links, li, blockquote, code, pre), at most 60,000 characters, nil
  when the feed has only a summary (under 280 characters). `summary` stays
  short plain text from description/summary. Mac: `FeedReader` in the
  Today/feed pane with a Text/Page switch (`ReaderBlock` is shared with the
  web pane). Phone: `MarkdownBlock` in `ReaderView`; a tap on a card with
  content opens the reader. A one-time reset (`feeds.contentV1`) clears
  ETags so followed feeds send full items again.
- Links into Sift (2026-11-15): the WindowGroup has
  `.handlesExternalEvents(matching: ["*"])` and the content
  `.handlesExternalEvents(preferring: ["*"], allowing: ["*"])`, so a
  feed:// or sift:// link goes to the open window, never a new one. Follow
  results use `AppModel.note` / `noteFollowed` (a fading capsule at the
  window's foot, runs folded into "and N more"), not the modal
  `exportMessage` alert.
- Feed fixes (2026-11-15): YouTube handle pages are fetched with a Safari
  user agent and the consent cookie (`SOCS=CAI; CONSENT=YES+cb`, cookies
  off for the request) and read the page's `feeds/videos.xml?channel_id=`
  link first (other `channelId` fields can be recommended channels).
  `FeedParser.parse` gives items that share one link (podcasts: the show
  page) their enclosure URL, else link#guid. The one-time ETag reset key is
  `feeds.contentV4` (1.4.3).
- Keyboard (2026-11-15, owner: "extensive keyboard shortcuts, google reader
  style"). `App/KeyMap.swift` is the one list (`KeyMap.bindings`: keys,
  action, title, group); `App/KeyRouter.swift` reads keys with a local
  NSEvent monitor in the main window only (not Settings, Setup Guide,
  Version History, sheets), never while a text field has focus or with ⌘ ⌃
  ⌥. "g" starts a two-key sequence (1.5 s). Lists take list keys through
  `KeyRouter.register(token, handler)` / `unregister(token)` (TabList,
  OfferedList); global keys go to the model (`navigationRequest`,
  `stepSidebar`, `showShortcuts`, `showAddFeed`). Keys: j/k n/p next and
  previous, o or Return opens the page, v the original in the browser, s
  keep (Today and feeds), m seen or unseen, Shift-A all seen, c copy, f
  follow the site, e send to the theme's destination, g t/a/u/k/r/x/d go
  to Today/Overview/Unsorted/Kept/Archive/Transcripts/Duplicates, Shift-J/K
  next or previous feed or theme, r refresh, / search, a Follow…, ? the
  shortcuts sheet (`Views/ShortcutsSheet.swift`, also Help > Keyboard
  Shortcuts ⌘/). A new shortcut is one `KeyBinding` plus its case.

- Command palette (2026-11-15): ⌘K, View > Go to…. `Views/CommandPalette.swift`
  (the panel, an overlay on ContentView while `AppModel.showPalette`) and
  `App/CommandPalette+Items.swift` (`PaletteCatalog` makes the items,
  `PaletteRanking` is the fuzzy match, `PaletteRecents` keeps the last 8
  places in UserDefaults `palette.recent`, `SettingsRoute` holds the one
  `SettingsNavigation` that SettingsView uses). Items: every sidebar place
  (go through `model.navigationRequest`), the Settings panes
  (`SettingsRoute.panes` must match `SettingsView.panes`), actions, "Follow
  <text>" when a non-catch-all provider or the web provider `matches`, and
  from 2 characters links by title (tabs + archive), Today picks and
  full-text hits (`searchLibrary`, 200 ms debounce). A link shows its list
  (theme, Archive or Overview) and opens in Safari. Demo mode leaves out
  network actions. A new sidebar place needs a row in `PaletteCatalog.places`.
- Reader first (2026-11-15, owner: "reader mode before opening weblink,
  like Reeder/NNW"). `Feeds/ArticleText.swift`: for summary-only items,
  fetch the page once (HostGate, Safari user agent), `Readable.extract`
  (Markdown), keep it in the feed file (`FeedStore.setContent`).
  `AppModel.fullText(for:)` returns feed text, kept text or a fetch (not
  YouTube); `fillTodayText` runs after each digest so today.json carries
  articles. Mac pane: `FeedReader` always first (summary and a spinner while
  fetching), Reader/Page switch. Phone: a tap always opens `ReaderView`.
- Originals open in Sift (2026-11-15, owner: "open original shud open in
  app, not safari (otherwise they become tabs and loop back into app)").
  Mac: `Views/BrowserWindow.swift`, a single `Window` (id "browser") on
  `model.browserURL`; `AppModel.openInApp(_:)` sets it, marks seen and bumps
  `browserRequest`, which ContentView turns into `openWindow`. Used by the v
  key, Go to links and links inside both readers (`OpenURLAction`). Phone:
  `ReaderView` opens the original and text links in `InAppBrowser`
  (SFSafariViewController). Only explicit "Open in Safari" items, the
  browser window's Safari button and double-clicking a tab row open Safari.
- Feed folders and totals (2026-11-15, owner). Folders are
  `Feed.category`; `moveFeed(_:to:)`, `renameFolder`, `deleteFolder` (feeds
  stay) in AppModel+Feeds. Sidebar: a feed's context menu has Move to Folder
  (existing, New Folder… alert, No Folder); feed rows are `.draggable(feed.id)`
  and folder rows drop targets; folder menu Rename…/Delete Folder. Totals:
  `feedItemCounts` (stored, refreshed by `refreshFeedCounts` on launch, after
  a check, follow and unfollow), folder total = sum. They count items held,
  not unread items.
- Reader beside the list (2026-11-15, owner: "standard macos patterns").
  TabList and OfferedList use `Views/ReaderSplit.swift`: an HStack of the
  list (min 300) and the pane (min 360, width in AppStorage
  `reader.width`) on `textBackgroundColor`, with a draggable divider. The
  minimum widths reach the window, so the sidebar never slides out. Not
  `HSplitView`: its minimums did not reach the window and the window
  shrank under the content. Seen items show grey pictures and icons,
  unseen in colour (`FeedIconView(grey:)`, `.saturation`). TodayRow shows the content's first paragraph
  when the summary is under 12 characters ("…").
- Unsorted in the Library box (2026-11-15, owner): `LibraryStatus` shows
  "N not in a theme" with a Sort menu button (primary: Sort into Themes;
  menu: Discover Themes Again). `UnsortedBanner` shows only before themes
  exist. Untitled feed items take `FeedParser.Text.title` (first line of the
  text, about 90 characters); a digest with URL titles rebuilds at once.
  `fullText` skips YouTube, bsky.app and Mastodon status URLs, and short
  summaries (under 280 characters, not ending in "…").
- Reader text fixes and site icons (2026-11-15). `PreviewFetcher.plain`
  folds all whitespace, so `FeedParser.Text.markdown` carries line breaks
  through it as U+001E and restores them. Emphasis tags move inner spaces
  outside the markers. `refreshTodayText` updates today's picks after each
  check; reset key `feeds.contentV3`. `Feeds/FeedIcons.swift`: one try per
  feed (`feedIconTried`), the site's apple-touch-icon.png else favicon.ico,
  saved as PNG in feeds/icons; `FeedIconView` shows it desaturated (rows
  without a picture, sidebar). No third-party icon service.
- Phone Today cards (2026-11-15, owner: "cards … sparse"): `CardView(lede:
  true)` from TodayCard shows the first blocks of the full text (Markdown,
  up to 8, faded at the bottom) instead of the summary when the text is
  longer than the summary; the picture shrinks to 200 pt then. Library deck
  cards are unchanged.
- Phone signals (2026-11-15, owner: "watch time" for the Today ranking).
  The prototype writes `iCloud Drive/Sift/signals/iphone-<id>.json`
  (`prototypes/ios-deck/App/Signals.swift`): a JSON array of events, newest
  last, at most 2,000: `{id, feedID, url, kind, seconds (number or null),
  at (ISO 8601)}`. Kinds: `dwell` (on screen 1.5 s or more), `skip` (less),
  `open`, `keep`, `unseen`, `play`. Today picks only. One file per device,
  like `seen/` and `kept/`. `TodayPick.vertical` (optional) marks a
  vertical video (YouTube Shorts) for the phone's full-card player.
- Today ranking (2026-11-15, owner: "think like tiktok/instagram but for
  rss"; "popularity of link in my feeds shud also be SIGNAL"). See
  `TodayBuilder.build` and `Feeds/Signals.swift`. `Feed.priority` (nil =
  Auto: Best Only above `FeedPriority.busyPerDay` = 5 posts a day, from
  `postsPerDay` over the span the items cover). Order: Don't Miss (14 days,
  until seen), Hot (same `linkKeys` in 2+ feeds; aggregator items also count
  for the article they link), then score = freshness × 1/sqrt(posts per day)
  × (1 + 0.8 × affinity) + theme fit (3+ shared words) + cross-mentions; Best
  Only needs a strong signal and gets 1 slot, Normal 2, Not in Today 0; one
  exploration slot (feed with < 3 signals), one wildcard from an unused
  feed. Affinity: `FeedSignals.affinity` over this Mac's `signals.json`
  (keep, reader open) and `iCloud Drive/Sift/signals/*.json` from phones,
  30-day decay, tanh to -1…1. `markShorts` sets `TodayPick.vertical` (HEAD
  youtube.com/shorts/<id>, no redirect). Phone: vertical cards
  (`VerticalVideo.swift`) for Shorts, all Instagram posts, TikToks; the
  player is made after the poster tap and plays at once (one tap). Library
  is one level (DeckView); StreamView stays in code, unused.

- Follow sheet (2026-11-15, owner: "top notch"). `Views/AddFeedSheet.swift`:
  finds while you type (700 ms pause, only input that looks complete),
  starts from an address or handle on the clipboard, takes a dropped link
  or OPML file (`readOPML(_ file:)`), shows cadence ("about 3 posts a week
  · last post 2 days ago") and the 3 newest titles, folder (with New
  Folder…) and In Today priority before Follow, Undo and Show after.
  "Popular" lists the Worker's well-known feeds (`Telemetry.loadKnownFeeds`,
  fetched only while usage counts are on), minus the ones followed.
- Feeds shared with the phone (2026-11-15, owner). `App/AppModel+FeedSync.swift`:
  the Mac writes `iCloud Drive/Sift/Deck/feeds.json` (feeds, no items, and
  `requests`: id → working/followed/failed/done) whenever the list changes;
  the phone writes `follows/iphone-<id>.json` (`PhoneFeedRequest`: follow
  with the typed input, unfollow, priority, folder). `mergeDeviceFollows`
  runs from `loadSeen` (launch, library rounds, app active) and handles
  each id once (`state.phoneRequests`). The Mac is the only fetcher. Phone:
  `prototypes/ios-deck/App/FeedsSync.swift`, Lists > Feeds.
- How Today Works (2026-11-15, owner: the ranking must be clear and
  visible). `Views/HowTodayWorks.swift`: the rules in plain words and each
  feed's live standing (`AppModel.standings`: priority and whether Auto
  chose it, posts a day, what Sift learned from signals) with a priority
  menu. Opened from Today's toolbar (?), Help > How Today Works and the
  bar above a single feed's list (`FeedStandingBar`). The text states
  `TodayBuilder.build`'s numbers: change both together.
- Install and icons: `build-app.sh` unregisters the build copy in
  build/DerivedData from LaunchServices; a registered build copy kept the
  old icon in the Dock.
- New Themes from Unsorted (2026-11-15, owner: add themes for what does not
  fit, keep the rest). `AppModel.discoverNewThemes` sends only unsorted,
  non-errand links (preview cut to 100 characters) to
  `Sorter.discoverNewThemes` with the current themes fixed; a link that
  fits one comes back under its exact name with kind "existing".
  `themeProposalAdditive` puts ThemeReview in additive mode;
  `applyNewThemes` appends new themes and fills only empty assignments
  (never a hand move, never a sorted link). Discover Themes Again still
  rebuilds the whole set and resets the mode.
- Merge themes (2026-11-15, owner). `AppModel.mergeTheme(_:into:)` moves
  every assignment (hand moves too), rewrites `also` without duplicates or
  self-links, appends the source's history and notes, keeps the target's
  `sendTo` (else the source's), removes the source. UI: `Views/MergeTheme.swift`
  (`MergeThemeMenu` + `.mergeConfirmation`), in the sidebar theme context
  menu and Settings > Themes.
