# Sift

A native macOS app for the hundreds of Safari tabs you keep open "for later".

Most of those tabs are not junk. Each one is a link you kept because it might
help with something you are working on. Safari keeps the link and forgets why
you kept it. Sift reads your tabs, sorts each one into the project it belongs
to, writes one line on how you could use it, and suggests what to do with it
next. Then you can close it.

The principle: a tab is a decision you have not made yet. Sift makes the
decision cheap, so the tab can leave the browser.

## How it works

Sift reads the tabs that Safari syncs to your Mac through iCloud, so your
iPhone and iPad tabs show up too. It also reads your Reading List. You pick
the source in the toolbar.

Sift can sort into themes or into projects. **Discover Themes** sends every
link it can see (your phone's tabs and the Reading List) to your own Claude in
one call and asks what you keep coming back to. You get 12 to 20 themes with a
description, the links behind each one and a suggested home for them. You
rename, untick or accept them; nothing changes before you do. Run it again
later and Claude keeps the theme names that still fit.

Without themes, Sift sorts into projects: git repos in a folder you choose
(`~/Dev` by default), with a short description from each README, plus any
projects you add by hand. With themes, those projects become the places a
theme's links can go.

Press **Sort with Claude**. For each tab, Claude picks a project, writes how
the link could be used there, and picks a next action:

| Action  | Meaning |
| ------- | ------- |
| Read    | Read or watch it properly: a long article, paper, talk or book |
| Try     | Install, test or prototype with it: a tool, repo, app or method |
| Cite    | Quote or reference it in writing, a deck, a pitch or a spec |
| Contact | Reach out to the person, company or community behind it |
| File    | Keep it as reference for the project; nothing to do now |
| Close   | Already used, outdated or not worth more time |

Tabs that belong to no project go to three buckets: personal, drop and
unknown.

The sidebar has four ways in: by project, by next action, by site (x.com,
github.com and so on) and by bucket. Every list shows cards with the page's
image, title and description. The overview draws one hub per project with a
dot for each tab, so you can see where your attention went.

You can move any tab by hand. Sift never overwrites a choice you made.

### Closing tabs on the iPhone

A Mac cannot close tabs on another device. Sift writes the tabs you mark to
`iCloud Drive/Sift/close.txt`, and a Shortcut on the iPhone closes them. The
app shows the steps to build the Shortcut once (Safari's Shortcut actions need
iOS 17 or later). When you reload, closed tabs leave the list.

### What Sift sends where

Sorting sends each tab's title, URL and preview text, plus your project names
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

**Projects** sets the projects folder, adds projects without a repo and hides
repos you do not want as projects.

File > Import Sorted CSV loads a sorting from a CSV with `project`, `url` and
`possible use` columns. Imported rows count as sorted by hand.

## Architecture

About 2,000 lines of SwiftUI. No dependencies.

| | |
| --- | --- |
| `Storage/CloudTabsReader` | Reads `CloudTabs.db` (SQLite, read-only): devices and their tabs |
| `Storage/ReadingListReader` | Reads the Reading List from `Bookmarks.plist` |
| `Storage/ProjectScanner` | Finds git repos and reads a summary from each README |
| `Storage/Previews` | Page previews (Open Graph, X oEmbed) and the iPhone close list |
| `Storage/StateFile` | Everything Sift remembers, as one JSON file in Application Support |
| `Sorting/Sorter` | One prompt and one JSON schema; runs through `claude -p` or the Messages API |
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
- One tab belongs to one project.

## License

MIT. See [LICENSE](LICENSE).
