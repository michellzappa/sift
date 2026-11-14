# Sift

A native macOS app for everything you saved "for later": open tabs on all
your devices, your Reading List, Instagram saves, X bookmarks and exports
from read-later tools.

Most of those links are not junk. Each one is a small promise to yourself:
this could matter. The browser keeps the link and forgets the promise. Sift
reads the pile back to you as the themes you keep coming back to, gives each
link an honest next step, keeps the text of every page in a library on your
Mac, and remembers what a link was about after the tab is gone.

The principle: your sprawl is not a problem to fix. It is a record of your
curiosity, and Sift makes it legible.

## What it does

### Sources

The source picker in the toolbar reads, all read-only:

- **Open tabs** that Safari syncs from your iPhone, iPad and other Macs
  through iCloud.
- **Safari's Reading List.**
- **Instagram Saved**, from Instagram's data export. In Instagram's Accounts
  Center, open Download your information and ask for JSON (HTML does not
  work), then choose the zip in Settings > Inputs.
- **X Bookmarks**, with the optional X API connection.
- **Imported files**: File > Import Links File reads Instapaper and Pocket
  CSV, Readwise Reader and Raindrop CSV, Pinboard JSON, and the bookmarks
  HTML that browsers and most tools export. Sift finds the URL, title,
  folder or tags and date by name. Each file is its own source.
- **YouTube Watch Later and playlists**, from a Google Takeout export of
  "YouTube and YouTube Music" (the YouTube API cannot read Watch Later).
  Import the Takeout zip with File > Import Links File.
- **All Sources**: everything above together, each link once, newest first,
  with a small icon for where it came from.

### Themes

There is no folder structure to set up. **Discover Themes** sends every link
to your own Claude in one call and asks what you keep coming back to. You get
12 to 20 themes in Title Case, each with a description, the links behind it
and a suggested home. You rename, untick or accept them; nothing changes
before you do. Run it again later and Claude keeps the names that still fit,
so links do not reshuffle. There is one set of themes for every source.

New links that are in no theme yet show as a grey cluster, and a banner
always offers the next step: **Discover Themes Again** to read everything
together, or **Sort into Current Themes**, which is cheaper.

Tabs that are open for a task rather than out of curiosity (orders,
accounts, carts, searches, dashboards, documents being edited) go to an
**errands** bucket. Sift spots the clear ones by URL and never sends them to
Claude; they stay out of themes, the graph and exports. The other buckets
are personal, drop and unknown. You can move any link by hand, and Sift
never overwrites a choice you made.

### Graph

The overview is a graph that loads in place. Each theme is a node with its
links around it as dots, and lines join themes that draw on the same sources
(the same site, or posts that link to the same domain). Colors are spread
evenly around the color wheel for however many themes you have, at equal
lightness, in light and dark mode. Hover a theme and the others fade.

Click a theme and the camera glides onto it: its links appear as cards in a
grid. Pinch or two-finger scroll to zoom the map; inside a theme, scrolling
moves the cards. Esc or a click on empty space zooms back out.

### Cards and the browser

Every link is a card: the page image, where it is from and when, the full
title, a short summary, how you could use it, and its next action. Click a
card and the page opens in a browser that slides in over the right side, so
the grid never moves. The browser has back, forward, reload, Open in Safari,
Add to Reading List and, for pages in the library, a reader view of the
saved text. The sidebar also lists links by next action, by site and by
bucket.

### Next actions

Each link gets one of six next steps, set by Claude or by you:

| Action  | Meaning |
| ------- | ------- |
| Read    | Read or watch it properly: a long article, paper, talk or book |
| Try     | Install, test or prototype with it: a tool, repo, app or method |
| Cite    | Quote or reference it in writing, a deck, a pitch or a spec |
| Contact | Reach out to the person, company or community behind it |
| File    | Keep it as reference; nothing to do now |
| Close   | Already used, outdated or not worth more time |

### Archive

Sift keeps a record of every link it has seen: title, theme, use, next
action, preview and dates. When a link leaves its source (a tab closed on
the phone, an item removed from the Reading List or an export), the record
moves to **Archive** instead of being forgotten.

### Library

Sift saves the readable text of every link into a library on your Mac: one
Markdown file per link, with the URL, title, author, site, theme and date at
the top, in `~/Library/Application Support/Sift/Library/`. Articles keep
their headings, paragraphs and lists; PDFs keep their text; posts keep their
text (Instagram posts their caption); YouTube videos keep their title,
channel and full description, which usually includes the chapters. Video
transcripts are not saved: YouTube serves captions only to its own player
and to a video's owner. Errands are skipped. Capture runs on
its own in the background, with a progress bar at the foot of the sidebar,
and does not use Claude. When a tab closes, its text stays.

### X posts

Without setup, X posts show their text through X's public oEmbed endpoint.
An opt-in setting uses X's embed data for images, avatars and the real URLs
behind t.co links (unofficial, may stop working).

With your own X developer app connected (optional, and X bills your
developer account per post read), Sift draws posts natively with no web
page: author, full text, images, video, quoted posts and links, following
X's display requirements. It reads posts in batches of 100, caches them,
refreshes a post only when its copy is older than a week, and drops posts
that X no longer returns. It can also bring in your 800 most recent
bookmarks.

To connect: create a Native App in the X Developer Console with callback URL
`http://127.0.0.1:53682/callback` and the scopes `tweet.read`, `users.read`,
`bookmark.read` and `offline.access`. Paste its Client ID in Settings >
Inputs > X and click Connect.

### Closing tabs on the iPhone

A Mac cannot close tabs on another device. Sift writes the tabs you mark to
`iCloud Drive/Sift/close.txt`, and a Shortcut on the iPhone closes them. The
app shows the steps to build the Shortcut once (iOS 17 or later): split the
list by lines, and for each address find the tab, switch to it and close
it.

### Export

The Export menu writes your themes and links out:

| Exporter | What you get |
| --- | --- |
| Obsidian Vault | One note per link and per theme with front matter and [[wikilinks]], so Obsidian's graph view shows themes as hubs. Your text under "## Notes" survives re-exports. |
| Markdown File | One file, a section per theme |
| Copy as Markdown | The same, on the clipboard |
| CSV File | One row per link; File > Import Sorted CSV reads it back |
| JSON File | The full snapshot, for scripts |

Each exporter is one Swift file. Adding one is the easiest way to
contribute; see [CONTRIBUTING.md](CONTRIBUTING.md).

### What Sift sends where

- **To Claude**, through your Claude Code login or your own API key: for
  theme discovery, sorting and next actions, each link's title, URL and short
  preview text, plus your theme names. Never whole pages. Errands never go
  to Claude.
- **To each site**, once: a request for its page, for the preview and the
  library. X posts go to X's oEmbed endpoint, and to its embed data or API
  only if you turn those on.
- **Nowhere else.** Sift has no account and no server. It reads Safari's
  files and never writes to them. Add to Reading List asks Safari through its
  own scripting command, and macOS asks you to allow that once.

## Requirements

- macOS 14 (Sonoma) or later
- Full Disk Access, to read Safari's synced tabs and Reading List
- One of: [Claude Code](https://claude.com/claude-code) signed in (the
  default; Sift runs `claude -p` with tools, MCP servers and settings turned
  off), or an Anthropic API key in your keychain
- Optional: iCloud Tabs on, for tabs from other devices

## Install

Download the latest `Sift-x.y.z.zip` from
[Releases](https://github.com/michellzappa/sift/releases), unzip it and move
Sift to Applications. Releases are signed with a Developer ID, notarized by
Apple, and carry a build provenance attestation. To check that a download
came from this repository's release workflow:

```sh
gh attestation verify Sift-0.2.0.zip -R michellzappa/sift
```

Each release also has a `SHA256SUMS` file.

On first launch Sift asks for Full Disk Access. macOS does not list the app
until you add it: in System Settings, open Privacy & Security, then Full Disk
Access, click +, and choose Sift.

### Build it yourself

```sh
./scripts/build-app.sh      # builds, signs and copies to /Applications/Sift.app
```

You need Xcode and `xcodegen`. Set your own `DEVELOPMENT_TEAM` in
`project.yml` first. The build number is the git commit count.

`project.yml` signs with an Apple Development identity, not ad hoc, because
macOS ties the Full Disk Access grant to the code signature: an ad hoc build
loses the grant on every rebuild. Set `SIGN_IDENTITY` to use another
identity. The app icon comes from the `sift` glyph in HouseKit, the small
package Sift shares with Tessellate, Cargo and Clip; without HouseKit next to
this repo, the script uses the committed `AppIcon.icns`.

### Releases

Push a tag that matches `CFBundleShortVersionString`, for example `v0.2.0`.
The workflow in `.github/workflows/release.yml` builds a universal app,
signs it with Developer ID, notarizes and staples it, attests its provenance,
and publishes the ZIP and `SHA256SUMS`. It needs these repository secrets:
`APPLE_TEAM_ID`, `APPLE_DEVELOPER_CERTIFICATE_P12_BASE64`,
`APPLE_DEVELOPER_CERTIFICATE_PASSWORD`, `APPLE_API_KEY_ID`,
`APPLE_API_ISSUER_ID` and `APPLE_API_PRIVATE_KEY_BASE64`.

## Settings

**Inputs** lists every source with its status and actions: Safari tabs
(devices and tab counts, the tab database, Full Disk Access), the Reading
List, the Instagram export, X (preview options and the optional X API
connection with Sync Bookmarks), imported link files, and library capture
(automatic capture, saved, thin and failed counts, Show Library in Finder).

**Outputs** runs each exporter and shows its last folder or file, shows the
iPhone close list and the Shortcut guide, and explains Add to Reading List
(Safari asks once for Automation permission).

**Claude** chooses Claude Code or an API key (`claude-opus-5-5` at low
effort) and stores the key in the keychain.

**Themes** lists your themes. You can rename or delete one, add one by hand,
or run Discover Themes again.

## Architecture

About 5,500 lines of SwiftUI. No dependencies.

| | |
| --- | --- |
| `Storage/CloudTabsReader` | Safari's synced tabs (`CloudTabs.db`, SQLite, read-only) |
| `Storage/ReadingListReader`, `InstagramReader`, `LinkImporter` | The other sources |
| `Storage/Previews` | Page previews (Open Graph, X oEmbed and embed data) and the iPhone close list |
| `Storage/Archive` | Every link Sift has seen, and what it knows about it |
| `Storage/StateFile` | Settings, themes and assignments, as one JSON file |
| `Engine/Capture` | Page capture, text extraction and the Markdown library |
| `Sorting/Sorter` | Theme discovery, sorting and next actions through `claude -p` or the Messages API |
| `Sorting/Errands` | Rules for transactional tabs |
| `X/*` | Optional X API: sign-in, client, cache and the native post view |
| `Export/*` | The exporter protocol, the registry and one file per exporter |
| `Views/*` | Sidebar, graph, cards, browser pane, theme review, settings |

Swift has no official Anthropic SDK, so the API backend uses plain HTTP.

## Limitations

- Sift cannot close tabs from the Mac; closing goes through the iPhone
  Shortcut.
- Sift cannot remove items from the Reading List or from imported files.
- Pages behind a login have no preview and only thin text in the library.
- Instagram posts show the caption from your export, not the image.
- One link belongs to one theme.

## License

MIT. See [LICENSE](LICENSE).
