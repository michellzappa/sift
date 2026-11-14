# Sift

A native macOS app for the hundreds of Safari tabs you keep open "for later".

Most of those tabs are not junk. Each one is a link you kept because it might
help with something you are working on. Safari keeps the link and forgets why
you kept it. Sift reads your tabs, sorts each one into the theme it belongs
to, writes one line on how you could use it, and suggests what to do with it
next. Then you can close it.

The principle: a tab is a decision you have not made yet. Sift makes the
decision cheap, so the tab can leave the browser.

## How it works

Sift reads the tabs that Safari syncs to your Mac through iCloud, so your
iPhone and iPad tabs show up too. It also reads your Reading List. You pick
the source in the toolbar.

Sift can also read the posts you saved on Instagram. In Instagram's Accounts
Center, open Download your information and ask for your information in JSON
format (an HTML export does not work). When the export arrives, choose the zip
or its unpacked folder in Settings > Sorting > Sources. **Instagram Saved**
then shows in the source picker. Each saved post becomes a link with its
author, caption and collection, and Discover Themes includes them. Sift reads
the export and never changes it.

There is no folder structure to set up. **Discover Themes** sends every link
Sift can see (your phone's tabs, the Reading List and Instagram Saved) to your own Claude in
one call and asks what you keep coming back to. You get 12 to 20 themes, each
with a description, the links behind it and a suggested home. You rename,
untick or accept them; nothing changes before you do. Run it again later and
Claude keeps the theme names that still fit, so your links do not reshuffle.

After that, **Sort with Claude** handles new tabs: it picks a theme, writes
how the link could be used, and picks a next action:

| Action  | Meaning |
| ------- | ------- |
| Read    | Read or watch it properly: a long article, paper, talk or book |
| Try     | Install, test or prototype with it: a tool, repo, app or method |
| Cite    | Quote or reference it in writing, a deck, a pitch or a spec |
| Contact | Reach out to the person, company or community behind it |
| File    | Keep it as reference; nothing to do now |
| Close   | Already used, outdated or not worth more time |

Tabs that belong to no theme go to four buckets. **Errands** holds
transactional tabs, pages open for a task rather than out of curiosity:
orders, accounts, carts, bookings, searches, dashboards, documents being
edited. Sift spots the clear ones by URL and never sends them to Claude for
theme discovery; Claude catches the rest. Errands stay out of themes, the
graph and exports. The other buckets are personal, drop and unknown.

The sidebar has four ways in: by theme, by next action, by site (x.com,
github.com and so on) and by bucket. Every list shows cards with the page's
image, title and description; select one and it opens in the browser on the
right. The overview is a graph: each theme is a cluster with one dot per link,
and lines join themes that draw on the same sources. Click a theme to zoom in
to its links; click a link to read it beside the graph. Pinch or two-finger
scroll to zoom.

### X posts, natively (optional)

With your own X developer app connected, Sift draws X posts as native views,
with no web page: author, full text including long posts, images, video,
quoted posts and real links. It can also bring in your bookmarks as a source.
X bills your developer account per post read (about half a cent), so Sift
reads posts in batches of 100, caches them, and refreshes a post only when
its copy is older than a week. Posts that X no longer returns lose their
content, as X's policy requires.

To connect: create a Native App in the X Developer Console with callback URL
`http://127.0.0.1:53682/callback` and the scopes `tweet.read`, `users.read`,
`bookmark.read` and `offline.access`. Paste its Client ID in Settings >
Sorting > X API and click Connect. Without it, X posts use the free oEmbed
preview as before.

### Export

The Export menu (toolbar and File menu) writes your themes and links out:

| Exporter | What you get |
| --- | --- |
| Obsidian Vault | One note per link and per theme with frontmatter and [[wikilinks]], so Obsidian's graph view shows themes as hubs. Your text under "## Notes" survives re-exports. |
| Markdown File | One file, a section per theme |
| Copy as Markdown | The same, on the clipboard |
| CSV File | One row per link; File > Import Sorted CSV reads it back |
| JSON File | The full snapshot, for scripts |

Each exporter is one Swift file. Adding one is the easiest way to
contribute; see [CONTRIBUTING.md](CONTRIBUTING.md).

You can move any tab by hand. Sift never overwrites a choice you made.

### Closing tabs on the iPhone

A Mac cannot close tabs on another device. Sift writes the tabs you mark to
`iCloud Drive/Sift/close.txt`, and a Shortcut on the iPhone closes them. The
app shows the steps to build the Shortcut once (Safari's Shortcut actions need
iOS 17 or later). When you reload, closed tabs leave the list.

### What Sift sends where

Sorting sends each tab's title, URL and preview text, plus your theme names
and descriptions, to Claude. It never sends page contents.

To build previews, Sift requests each page once from its own site. For posts on
X it uses X's public oEmbed endpoint, which returns the post text without a
login.

An opt-in setting (Settings > Sorting > Previews, off by default) makes Sift ask
X's syndication endpoint (cdn.syndication.twimg.com) first, which also returns
post images. The endpoint is unofficial and can stop working at any time.

Sift reads Safari's files and never writes to them.

## Requirements

- macOS 14 (Sonoma) or later
- Safari with iCloud Tabs on, for tabs from other devices
- Full Disk Access, to read Safari's tab database and Reading List
- One of:
  - [Claude Code](https://claude.com/claude-code), signed in (the default; Sift runs `claude -p`)
  - an Anthropic API key, stored in your login keychain

## Install

There is no notarized release yet. Build it yourself:

```sh
./scripts/build-app.sh      # builds, signs and copies to /Applications/Sift.app
```

You need `xcodegen` and Xcode. Set your own `DEVELOPMENT_TEAM` in
`project.yml` first. To work in Xcode instead, run
`xcodegen generate && open Sift.xcodeproj`.

On first launch Sift asks for Full Disk Access. macOS does not list the app
until you add it: in System Settings, open Privacy & Security, then Full Disk
Access, click +, and choose Sift.

### A note on signing

`project.yml` signs with an Apple Development identity, not ad hoc. macOS ties
the Full Disk Access grant to the code signature, so an ad hoc build loses the
grant on every rebuild. Find your identity with:

```sh
security find-identity -v -p codesigning
```

The build script signs with `Apple Development` by default. Set
`SIGN_IDENTITY` to use another one.

The app icon comes from the `sift` glyph in HouseKit, the small package that
Sift shares with Tessellate, Cargo and Clip. If HouseKit is not checked out
next to this repo, the script uses the committed `AppIcon.icns`.

## Configuration

Settings has two pages.

**Sorting** chooses between Claude Code and an API key. With Claude Code, Sift
runs `claude -p` with tools, MCP servers, skills and settings turned off, so
each call costs about as many tokens as the tab list itself. With an API key,
Sift calls the Messages API with `claude-opus-5-5` at low effort.

**Themes** lists your themes. You can rename or delete one, add one by hand,
or run Discover Themes again.

File > Import Sorted CSV loads a sorting from a CSV with `project`, `url` and
`possible use` columns. Imported rows count as sorted by hand.

## Architecture

About 2,800 lines of SwiftUI. No dependencies.

| | |
| --- | --- |
| `Storage/CloudTabsReader` | Reads `CloudTabs.db` (SQLite, read-only): devices and their tabs |
| `Storage/ReadingListReader` | Reads the Reading List from `Bookmarks.plist` |
| `Storage/Previews` | Page previews (Open Graph, X oEmbed) and the iPhone close list |
| `Storage/StateFile` | Everything Sift remembers, as one JSON file in Application Support |
| `Sorting/Sorter` | Theme discovery and sorting; runs through `claude -p` or the Messages API |
| `Export/*` | The exporter protocol, the registry and one file per exporter |
| `App/AppModel` | Loading, sorting, actions and the close list |
| `Views/*` | Sidebar, card grid, overview network, preview pane, settings |

Swift has no official Anthropic SDK, so the API backend uses plain HTTP.

## Limitations

- Sift cannot close tabs from the Mac. Closing goes through the iPhone
  Shortcut.
- Sift cannot remove items from the Reading List. Safari rewrites
  `Bookmarks.plist` while it runs, and editing it from outside is not safe.
- Previews for X posts have text but no image. Pages behind a login have no
  preview.
- One tab belongs to one theme.

## License

MIT. See [LICENSE](LICENSE).
