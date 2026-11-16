# sift-mcp: tools for Claude

`sift-mcp` is an MCP server inside Sift.app
(`/Applications/Sift.app/Contents/MacOS/sift-mcp`, stdio). It gives your own
Claude your Sift library: links, saved page text, transcripts, summaries,
themes, feeds and Today.

## Add it

Settings > Intelligence > Add to Claude Code runs:

    claude mcp add --scope user sift -- /Applications/Sift.app/Contents/MacOS/sift-mcp

Any other MCP client works with the same command.

## How it works

- **Reading tools** read Sift's search index
  (`~/Library/Application Support/Sift/search.sqlite`) read-only. They work
  while Sift is closed.
- **Acting tools** never write Sift's files. Each call leaves a request in
  `~/Library/Application Support/Sift/agent/requests/`. The running app
  takes it and calls the same code a button calls, then writes the result.
  If Sift is closed, `sift-mcp` opens it in the background first. A call
  waits up to 20 seconds (45 after a launch) for the result.
- **Long jobs** (`sort_unsorted`, `propose_new_themes`, `check_feeds`)
  answer "started" with a job id. `job_status` reads the result later.
- Every request and its outcome goes into `agent/log.jsonl`. Settings >
  Intelligence lists the recent ones, and `agent_log` returns them.
- Nothing goes to a Sift server. `send` is the only tool whose effect leaves
  the Mac (to your own destination), and Claude is told to confirm it with
  you first.
- In demo mode the acting tools refuse. `sift-mcp` does not know demo mode
  and still reads your real index.

## Reading tools

| Tool | Arguments | Returns |
| --- | --- | --- |
| `search` | `query` (plain words), `theme` (optional), `limit` (1-50, default 10), `include_hidden` (default false) | Full-text hits over titles, page text, transcripts, previews and summaries. Leaves out links you dropped as noise and errands unless `include_hidden`. Ranks links you kept, sent or noted first, and seen ones a little higher. Shows those marks. |
| `get_link` | `url` (exactly as `search` or `theme_links` returned it) | One link: title, theme, related themes, source, kind, saved date, marks, a summary when Sift has one, and the saved text or transcript as Markdown (up to 40,000 characters). |
| `list_themes` | none | Every theme with its link count, summary, and your notes and history for it. |
| `theme_links` | `theme`, `limit` (1-200, default 50) | The links in one theme, and links that also feed it, newest first, with title, URL, source and date. |
| `unsorted` | `limit` (1-500, default 50) | Links in no theme. |
| `list_feeds` | none | Every followed feed: folder, place in Today, posts a day, and what Sift learned from your reading. |
| `today` | none | Today's picks with the reason for each, seen or unseen, kept or not. |
| `list_destinations` | none | Your Send destinations, for `send`. |
| `job_status` | `id` | The result of a long job or any earlier call. |
| `agent_log` | `limit` (1-100, default 20) | The latest requests made through these tools and their outcome. |

## Acting tools

| Tool | Arguments | Effect |
| --- | --- | --- |
| `merge_themes` | `from`, `into` | Moves every link, note and history line of `from` into `into`, and removes `from`. There is no undo except moving links by hand. |
| `rename_theme` | `name`, `to` | Renames a theme. Links, notes and history stay with it. |
| `move_link` | `url`, `theme` | Files a link under a theme or the `drop`, `personal` or `errands` bucket. This is a hand move: sorting never overrides it. |
| `add_note` | `url`, `text` | Saves your note on a link. Search sees it. Empty text removes it. |
| `sort_unsorted` | none | Long job. Files every unsorted link into the current themes with your own Claude. |
| `propose_new_themes` | none | Long job. Proposes new themes for unsorted links that fit none of the current themes. Nothing changes yet; `job_status` returns the proposal and its id. |
| `apply_theme_proposal` | `proposal`, `accept` (theme names, default all), `rename` ("Old => New") | Adds the accepted new themes and files their links. Current themes and hand moves stay. |
| `follow` | `input`, `folder` (optional), `priority` (optional: `auto`, `must`, `normal`, `best`, `off`) | Follows anything the Follow sheet takes: a site, a feed address, `r/name`, `@name.bsky.social`, `@user@instance`, a YouTube channel or playlist, `podcast: name`, `news: words`. |
| `unfollow` | `feed` (title, address or id) | Stops following a feed and removes its items. |
| `set_feed_priority` | `feed`, `priority` | Sets the feed's place in Today: `auto`, `must` (Don't Miss), `normal`, `best` (Best Only) or `off` (Not in Today). |
| `move_feed` | `feed`, `folder` (leave out for no folder) | Puts a feed in a folder. |
| `check_feeds` | none | Long job. Fetches every feed and updates Today. |
| `mark_seen` | `urls`, `seen` (default true) | Sets the seen mark. It syncs to the iPhone app. |
| `keep` | `url` | Moves a Today or feed item into the library, like Keep in the app. |
| `send` | `url`, `destination` | Sends a link to one of your destinations (Starlings, Obsidian, Markdown, Reading List). This leaves the Mac. |

There is no tool to delete a theme. That stays a choice you make in the app.

## Examples

- "What have I saved about urban heat islands, and what did those pages say?"
  uses `search`, then `get_link`.
- "Find themes for everything unsorted and apply the good ones" uses
  `propose_new_themes`, `job_status` and `apply_theme_proposal`.
- "Follow the three newsletters I save most from, Best Only" uses `search`
  or `list_feeds`, then `follow` with `priority: best`.

## Adding a tool

See "Adding a tool for Claude (sift-mcp)" in [CONTRIBUTING.md](../CONTRIBUTING.md).
Keep this file in step with `SiftMCP/Tools.swift` and `SiftMCP/AgentTools.swift`.
