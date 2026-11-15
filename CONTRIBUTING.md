# Contributing to Sift

Issues and pull requests are welcome. The easiest way in is a new exporter.

## Add an exporter

An exporter takes a snapshot of your sorted links and writes it somewhere:
a notes app, a read-later service, a file format. Each exporter is one Swift
file. You do not need to touch the rest of the app.

1. Copy `Sift/Export/MarkdownExporter.swift` to
   `Sift/Export/<Name>Exporter.swift` and rename the struct.
2. Set `id` (lowercase, stable), `name` (the menu title, ending in "…" when
   it asks for a folder or file), `summary` (one sentence) and `output`:
   - `.folder` when you write several files into a folder the user picks,
   - `.file(extension:)` for one file,
   - `.clipboard` when you return text to copy.
3. Write `export(_:to:)`. You get an `ExportSnapshot` with `themes` and
   `items`. Each item has the URL, title, theme, use, the destinations it was sent to, site,
   source, date, preview text and image URL. Return a short result message,
   or the text to copy for `.clipboard`.
4. Add one instance to `Exporters.all` in `Sift/Export/Exporter.swift`.
5. Add one line for it to the Export section of `README.md`.

Rules that keep exporters safe to merge:

- Read only the snapshot. No network calls, no keychain, no app state. An
  exporter that needs a service (an API, an account) should be proposed in an
  issue first, so we can agree how credentials work.
- Never delete files you did not write. If you rewrite files, keep user edits
  the way `ObsidianExporter` keeps everything under "## Notes".
- Plain, standard formats. No new dependencies.

`ObsidianExporter` is the fullest example: notes with frontmatter, wikilinks
between links and themes, unique file names and preserved notes.

## Build

You need macOS 14 or later, Xcode and `xcodegen`. Set your own
`DEVELOPMENT_TEAM` in `project.yml`, then:

```sh
xcodegen generate && open Sift.xcodeproj
```

or `./scripts/build-app.sh` to build, sign and install to /Applications.

## Other changes

Open an issue first for anything bigger than an exporter or a fix, so we can
agree on the shape before you spend time on it. Sift aims to stay small: it
is the step between saving a link and filing it, not a notes app.

## Adding a feed provider

A provider turns what someone types (a handle, an address, a name) into
feed addresses: `r/swift` becomes `reddit.com/r/swift/.rss`.

1. Create `Sift/Feeds/Providers/<Name>Provider.swift` with a struct that
   conforms to `FeedProvider` (`id`, `name`, `symbol`, `examples`,
   `matches(_:)`, `candidates(for:)`).
2. Add one instance to `FeedProviders.all` in `Sift/Feeds/FeedProvider.swift`,
   before `WebProvider`, which is always last.

`matches` must not touch the network: it decides, as the person types,
which provider shows in the Add sheet. `candidates` may ask the network
(YouTube reads the channel id from the page; Podcast asks Apple's
directory) and returns addresses best first; Sift fetches and checks each
one. Test the address forms with `curl` before you add them: a provider
that returns addresses that are not feeds only produces "no feed found".

## Adding a send destination

1. Create `Sift/Send/<Name>Sender.swift` with a struct that conforms to
   `Sender` (`kind`, `label`, `symbol`, `send(_:to:)`).
2. Add one instance to `Senders.all` in `Sift/Send/Sender.swift`.
3. Give Settings > Outputs > Send to a way to add a `Destination` of that
   kind (its settings go in `config`).
A sender gets one link at a time and returns where it landed (a URL or a
file path), or throws `SendFailure` with a message for the user.

## Adding an onboarding step

A new source, destination or library option can add its own page to the
Setup Guide. You do not edit the guide itself.

1. Create `Sift/Onboarding/<Name>Step.swift` with a struct that conforms to
   `OnboardingStep`: `id` (lowercase, stable, never renamed), `title`,
   `symbol` (an SF Symbol), `isOptional` (true unless the app cannot work
   without it), `status(_:)` and `body`.
2. `status(_:)` returns `.done`, `.available` or `.blocked`, each with one
   line that says why. The guide shows it as a dot in the step list.
   `.blocked` disables Continue, so use it only when the step cannot work
   yet (for example, no source has links).
3. `body` is the step's content. Read and change the app through
   `AppModel` from the environment. Reuse what Settings uses (for example
   `StatusRow` and the status properties in `Views/SourceStatus.swift`)
   instead of a second copy.
4. Add one instance to `Onboarding.steps` in
   `Sift/Onboarding/Onboarding.swift`, where it belongs in the flow.

People who already finished the guide see the new step once, under "New in
Sift". Sift records each step id it has shown in `onboardingSeen` in
`state.json`.

## Adding a tool for Claude (sift-mcp)

sift-mcp never writes Sift's state; the running app does (issue #34).

1. Add the tool's name to `AgentTools.writes` or `AgentTools.reads` in
   `Shared/AgentRequests.swift`.
2. Add its definition (name, description, input schema) to
   `AgentCalls.definitions` in `SiftMCP/AgentTools.swift`. Say in the
   description when the tool reaches outside the Mac.
3. Add a case to `AppModel.handle` in `Sift/App/AppModel+Agent.swift` that
   calls the same model function the app's button calls, and `finish`es
   with what changed. A long job: add it to `longJobs` and `finish` with
   "started" first.
