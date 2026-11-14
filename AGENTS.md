# Sift — agent notes

Sift is a native macOS app that turns open Safari tabs into project material.
It reads the iCloud Tabs database that Safari syncs to this Mac, sorts each tab
into one of mz's projects with Claude, and shows the result as a list per
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
- Sorting: `Sorter` calls the Messages API over HTTP (Swift has no official
  SDK). Model `claude-opus-5-5`, effort `low`, structured output with a
  project enum, server-side fallback on refusal. It sends titles and URLs
  only. Batches of 40.
- State: one JSON file, `~/Library/Application Support/Sift/state.json`,
  keyed by URL. Hand moves set `manual: true`; the sorter never overwrites them.
- API key: login keychain, service `app.sift.anthropic-api-key`.

## Decisions

- No HouseKit dependency: Sift is a window app, not a menu-bar app, and uses
  the SwiftUI Settings scene. Add HouseKit if it moves to the menu bar.
- Sift cannot close tabs on the iPhone. The database is a synced copy; writing
  to it does not change the phone.
- `*.csv` is ignored so exported tab lists (browsing data) never get committed.
