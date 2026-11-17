# Changelog

Every entry is a `v`-prefixed git tag. The version comes from
`CFBundleShortVersionString` in `Sift/Resources/Info.plist`.

Add a section here before you tag. The release workflow takes the GitHub
release notes from this file and refuses a tag that has no section. Sift
ships this file and shows it in Settings > About and in Sift > Version
History. Headings are `## X.Y.Z - YYYY-MM-DD`; groups are `### Added`,
`### Changed` and `### Fixed`.

## 1.7.8 - 2026-11-17

### Added
- Closeness in meaning, on your Mac and iPhone. Sift now reads what each saved link and recent feed item is about with Apple's on-device language model (part of macOS and iOS, no download, nothing sent anywhere). Trails use it to find items close in meaning even when they share no words. Today uses it as a soft theme fit, only when one theme clearly leads. "Why this is here" shows the number. The vectors are plain files in the embeddings folder.

## 1.7.7 - 2026-11-17

### Added
- Trails. Choose More Like This on any item, or press T, to open a trail: up to 20 unseen items near it from the same creator, the same theme or with words in common. They come from your saves and the last two weeks of your feeds. The trail ends, and you can start a new one from any item on it. Follow the creator from the top of the trail. On the iPhone, More Like This is at the end of every article and in each row's menu.
- Linked by your feeds. When a feed you follow links to an item in its posts this week, Today gives the item a lift and says who linked it. When two or more of your feeds link to something that no feed carries, it gets a place of its own in Today, at most three at a time. "Why this is here", Settings > Algorithm and How Today Works show the numbers.

## 1.7.6 - 2026-11-17

### Added
- Farther, a third tab in Your Graph. Pick a theme and ask your own Claude where the theme is going. It names sources one step beyond what you follow: deeper in the same direction, a neighbouring field your newest saves lean toward, and one serious different view. Sift checks each one for a feed, and only those with a feed can be followed. "What Claude saw" shows the exact text sent. On the iPhone, Farther is on each theme page, and Ask Claude there asks your Mac.

## 1.7.5 - 2026-11-17

### Added
- Next Door, a second tab in Your Graph. It lists creators outside your graph that two or more of yours link to, found in the pages, video descriptions and feed items Sift already has on your Mac. Each one shows who linked it and the links themselves. Sponsor links, shops, tip jars and a creator's own site do not count. Follow or hide from there. On the iPhone, Next Door shows on each theme page and in Your Graph.

## 1.7.4 - 2026-11-17

### Added
- Your Graph reaches the iPhone. The Mac shares it through iCloud Drive, and the phone can follow or hide a creator. The Mac does the following.

## 1.7.3 - 2026-11-17

### Added
- Settings > Algorithm shows everything Sift ranks by, with live numbers: the Today score formula, today's picks sorted by score, what each signal (keep, open, reading time, skip) adds, each feed's standing, Your Graph, and which features use Claude, Apple's on-device model or no AI at all.

## 1.7.2 - 2026-11-17

### Added
- Your Graph, in the sidebar under Feeds. It lists the YouTube channels, sites, writers, subreddits and repositories behind the links you saved, ranked by your saves (a save counts half after 90 days). Each one shows its themes, what you saved and how the score adds up. Follow a creator from there, or hide it. Nothing reaches Today until you follow it.
- Followed creators get a lift in Today by how many of their links you saved, with a reason line like "You saved 14 from Dwarkesh Patel".
- "Why this is here" under every Today pick: the rule that placed it and every number of its score.

### Fixed
- YouTube channel names with "&" were saved as "u0026".

## 1.7.1 - 2026-11-17

### Fixed

- Instagram posts and reels and TikTok videos play in the pane beside
  the list, without the login wall: Sift opens their embed page.
- Library lists use the full width again when the pane is open. Rows
  were squeezed and slid under the sidebar.

## 1.7.0 - 2026-11-17

### Added

- The Mac's Today rows show the top Hacker News and Reddit comments
  too, the same ones the iPhone shows, in Scan and All. Click the
  comment count to open the discussion.

## 1.6.9 - 2026-11-17

### Added

- Top comments for Hacker News and Reddit posts in Today. Sift fetches
  the top 3 comments from the public Hacker News and Reddit pages, paced,
  with no login, and the iPhone shows them under each Scan headline.

## 1.6.8 - 2026-11-17

### Changed

- Scan, Watch and Read each get a fair share of Today. When a mode has
  fewer than 5 picks, Sift adds unseen items of that mode from the last
  14 days, so Watch is not empty on a day your video feeds were quiet.
  Each mode also gets its own "New to you" and "Something different"
  pick. How Today Works explains the new rule.

## 1.6.7 - 2026-11-16

### Added

- Your YouTube playlists are saved links. Follow offers Add to Library for
  a playlist: its videos become a Library source, like Reading List, with
  transcripts and themes, and leave Today. A video you remove from the
  playlist moves to Closed or Removed. Any feed can switch with Move to
  Library as My List, and back with Show in Today Instead.

## 1.6.6 - 2026-11-16

### Added

- Settings > How It Works shows a diagram of Sift: what comes in, what Sift
  adds on your Mac, Library and Today, and what you do. The README and the
  website show the same diagram.
- iPhone: Scan, Watch and Read tabs each have a Today / Library switch, so
  saved links are split the same way as Today. The review deck moved to
  Lists.

### Changed

- Archive is now called Closed or Removed.
- The Source menu left the toolbar. Pick a source in the sidebar.

## 1.6.5 - 2026-11-16

### Changed

- Read now holds every blog, newsletter and article, short or long, so
  Daring Fireball and similar sites are in Read. Scan holds headline sites
  (Hacker News, Reddit, Google News) and posts.
- In Scan, a row you scroll past counts as seen, on the Mac and the iPhone.
- The blue unseen dot sits after the title on every list and card.

## 1.6.4 - 2026-11-16

### Changed

- Substack and Medium posts go to Read, including paid posts whose feed
  holds only the opening.

## 1.6.3 - 2026-11-16

### Added

- The iPhone app has Scan, Watch and Read tabs for Today. Sift on the Mac
  now writes each pick's mode into today.json, so both apps sort items the
  same way. Log moved to the top right of Lists.

### Changed

- Setting a feed's Mode on the Mac updates the iPhone's tabs at once.

## 1.6.2 - 2026-11-16

### Added

- Scan, Watch, Read: a switch at the top of every list. Scan shows
  headlines and posts as short rows without pictures. Watch shows videos as
  cards, with tall cards for Shorts, TikToks and reels. Read shows long
  texts with their reading time. Keys 0 to 3. It works the same in Today,
  feeds and your library.
- Mode in a feed's context menu sets Scan, Watch or Read for all of the
  feed's items.

## 1.6.1 - 2026-11-16

### Changed

- A followed YouTube playlist now brings in its first 100 videos, not only
  the 15 that YouTube's playlist feed holds. A video counts as new on the
  day you add it to the playlist, so a public or unlisted playlist works as
  a shared Watch Later list in Today.

## 1.6.0 - 2026-11-16

### Changed
- Help > Sift Guide and Help > Claude Tools open the documentation at michellzappa.com/apps/sift/docs.

## 1.5.9 - 2026-11-16

### Added
- Help > Sift Guide and Help > Claude Tools (sift-mcp) open the documentation.
- The README covers everything that shipped: Today and its ranking, Follow, the reader, keyboard shortcuts and Go to, seen and unseen, the Sort menu and Merge Into, transcripts, Claude's tools, the iPhone app and updates. `docs/mcp.md` lists every tool Claude can call.

## 1.5.8 - 2026-11-16

### Added
- TikTok as a source. Choose your TikTok data export (JSON) in Settings > Inputs or the Setup Guide. Sift reads your favourite videos, and liked videos when you turn that on.
- Each TikTok video gets its caption, author and cover from its public page, with no login. Covers stay on this Mac.
- TikTok speech becomes text the same way as Instagram reels: yt-dlp fetches the audio without cookies, and macOS speech recognition writes it down. When one platform refuses, the other keeps going.

## 1.5.7 - 2026-11-15

### Added
- Claude can act on your library through sift-mcp, not only read it: merge and rename themes, file a link, add a note, sort, propose and apply new themes, follow and unfollow feeds, set a feed's place in Today, check feeds, mark seen, keep and send. It can also read your feeds, Today, unsorted links and Send destinations. Sift makes each change itself, the same way a button does.
- Settings > Intelligence lists Claude's recent actions.
- Search through sift-mcp leaves out links you dropped as noise and errands, ranks what you kept, sent or noted first, and shows those marks.

## 1.5.6 - 2026-11-15

### Added
- Merge Into for themes: right-click a theme in the sidebar, or use the merge button in Settings > Themes. Its links, second themes, notes and history move to the other theme, after a confirmation.

## 1.5.5 - 2026-11-15

### Added
- New Themes from Unsorted (Sort menu in the Library box, and Settings > Themes): Claude reads only the links in no theme and proposes new themes for the ones that fit none of yours. Your themes and their links stay as they are. The review shows the new themes first, then the links that fit a theme you have; Add Themes and Sort files both.

## 1.5.4 - 2026-11-15

### Added
- The Community Pulse now shows inside Settings > Telemetry, as in Headroom: weekly active Macs, week over week, new and returning Macs, versions, sources, feeds followed, well-known feeds, destinations, library sizes, macOS, countries and feature adoption.

## 1.5.3 - 2026-11-15

### Changed
- The Privacy settings pane is now named Telemetry, so the usage report is easy to find.

## 1.5.2 - 2026-11-15

### Added
- How Today Works (Today toolbar, Help menu): how Today picks and orders items, in plain words, and for each feed its place in Today, how often it posts and what Sift learned from your reading.
- Above a feed's list: its place in Today, with a menu to change it, and what Sift learned about it.

### Fixed
- The Dock could show the old icon after an install.

## 1.5.1 - 2026-11-15

### Added
- Follow finds the feed while you type, and starts from an address on the clipboard.
- Each result shows how often the feed posts, when it last did and its newest titles.
- Pick a folder (or make a new one) and how the feed takes part in Today before you follow. Undo and Show after.
- Popular: large public feeds you do not follow yet, one click to follow.
- Drop a link or an OPML file on the Follow sheet.
- Your feeds show on the iPhone (Lists > Feeds). Follow, unfollow, change priority or folder there; your Mac does the work.

### Fixed
- The Feeds settings text no longer says Today updates at 07:00 and 17:00.

## 1.5.0 - 2026-11-15

### Added
- The weekly usage report counts the kinds of feed you follow (Substack, Reddit, podcasts and so on), never an address or name.
- It also names the feeds you follow that are on Sift's public list of large, well-known feeds. Any other feed never leaves your Mac. Settings > Privacy has a switch for this part.
- The Community Pulse shows feed kinds, and a well-known feed once 5 or more Macs follow it.

## 1.4.9 - 2026-11-15

### Changed

- **Today updates as your feeds post.** There is no longer a fixed 10 twice a day. New items that make the cut go on top as soon as a feed brings them, and items you have already seen stay where they are until they are three days old. Each feed has at most three unseen items in Today at a time, so a busy feed cannot fill it; the next one comes in as you read. The title says how many are new. Rebuild Today in the toolbar starts it again from nothing.

## 1.4.8 - 2026-11-15

### Changed

- The icon's card stack sits a little higher, so it looks centred.

## 1.4.7 - 2026-11-15

### Changed

- The icon's cards get smaller as well as fainter as they step back, in equal steps, and the stack sits in the centre of the icon.

## 1.4.6 - 2026-11-15

### Changed

- The icon's cards are now one size and step back at equal distances, each one fainter.

## 1.4.5 - 2026-11-15

### Changed

- **A new icon.** A stack of cards with the top one lifted: what Sift offers you, one card at a time. The iPhone app has the same icon.

## 1.4.4 - 2026-11-15

### Changed

- **No banner above Today.** The window title says how many items are new and when the next digest comes, as Mail shows its unread count.

## 1.4.3 - 2026-11-15

### Changed

- **Quiet blogs keep their posts.** Sift keeps the newest 20 items of every feed at any age, plus everything from the last 90 days. A blog that posts a few times a year now shows its back posts, not only the latest. Today still offers only recent items.

## 1.4.2 - 2026-11-15

### Changed

- **Unseen items show in colour, seen items in grey.** The picture and the site icon go grey once you have seen an item, like read mail.

### Fixed

- The window can no longer get narrower than the sidebar, the list and the reader together, so the sidebar stays in the window. The pane keeps the width you drag it to.
- Quotes in the reader show as quotes. Before, a stray ">" stood on its own line above them.

## 1.4.1 - 2026-11-15

### Changed

- **The reader is a real split view, as in Mail.** The list, a divider you can drag, and the page on its own white (or dark) background. This is the same in Today, feeds and saved links.

### Fixed

- The thin line that ran across the reader is gone.
- Items whose feed gives only "…" as a summary now show the article's first lines in the list.

## 1.4.0 - 2026-11-15

### Added

- **Today learns, like a For You page for your feeds.** Each feed has a place in Today: Auto (the default), Don't Miss, Normal, Best Only or Not in Today; right-click a feed and choose In Today. Auto puts busy feeds such as Hacker News on Best Only, so they show only when an item stands out. Don't Miss items come first and stay until you have seen them.
- **Rare posts count more.** A quiet blog's new essay outranks the thirtieth post of a busy feed.
- **Sift learns from what you do.** Keeping, reading and lingering on a card raise a feed; flicking past lowers it a little. The iPhone sends how long each card stays on screen. Recent behaviour counts most.
- **Hot.** When the same link is in two or more of your feeds (also when a Hacker News or Reddit post points to an article another feed has), it goes to the top with a flame: "Hot in 3 of your feeds".
- **Vertical video on the iPhone.** YouTube Shorts, Instagram posts and TikToks show as full cards: the picture first, one tap plays it in the card, swiping on stops it.
- **sift://today** opens Today and builds it again.

### Changed

- Today keeps one slot for a feed Sift knows little about yet, and its wildcard always comes from a feed not already in the digest.
- "Fits a theme" needs a closer match.
- On the iPhone, Library is one set of cards.

## 1.3.8 - 2026-11-15

### Changed

- Today no longer adds "New from …" under an item: the row already names the feed. Items that are there for a reason still say it (fits a theme, in several of your feeds, from a feed you often keep, something different).

## 1.3.7 - 2026-11-15

### Changed

- Site icons are smaller: in rows without a picture and in the sidebar.

## 1.3.6 - 2026-11-15

### Added

- **Site icons.** Each feed shows its site's icon beside it in the sidebar, and items without a picture show it in grey. Sift fetches the icon once from the site itself.

### Fixed

- Articles in the reader lost their paragraphs and line breaks, and bold text with a space inside (as Substack writes it) showed as **1: **. Sift fetches every feed once more so the text is right.

## 1.3.5 - 2026-11-15

### Changed

- **Unsorted links live in the Library box.** The count and the Sort button (Discover Themes Again is in its menu) moved from the bar above every list to the Library box at the foot of the sidebar. The bar shows only on the first run, before you have themes.

### Fixed

- Posts from Bluesky, Mastodon and other feeds without titles showed their address as the title. They now use the first line of the post.
- The reader no longer says it could not read the full article for a short post that is complete, and no longer tries to fetch Bluesky pages.

## 1.3.4 - 2026-11-15

### Changed

- **The reader sits beside the list.** Opening an item (Today, a feed or any list) makes the list narrower instead of sliding the page over it, so the list stays readable. The reader has a close button; Space still opens and closes it.

## 1.3.3 - 2026-11-15

### Added

- **Folders for feeds.** Right-click a feed and choose Move to Folder: an existing folder, a new one, or no folder. You can also drag a feed onto a folder. Right-click a folder to rename or delete it; its feeds stay.
- **Totals in the sidebar.** Each feed shows how many items it holds, and each folder the sum of its feeds.

## 1.3.2 - 2026-11-15

### Changed

- **Originals open inside Sift, not in Safari.** A page opened in Safari becomes a tab, and tabs come back into Sift as links. On the Mac, v, a link chosen in Go to and links inside the reader open in a Sift browser window, with back, forward and an explicit Open in Safari button. On the iPhone, Open the original and links in the reader open in Safari inside the app. The menu item Open in Safari still opens Safari.

## 1.3.1 - 2026-11-15

### Changed

- **Reader first, like Reeder and NetNewsWire.** An item from Today or a feed always opens in the reader, with a Reader and Page switch for the website. When a feed sends only a summary, Sift fetches the article once, keeps its text, and shows it there. Today's items get their full text as soon as the digest is built, so the iPhone has it too. On the iPhone, a tap always opens the reader; Open the original is at the end.

## 1.3.0 - 2026-11-15

### Added

- **Keyboard shortcuts in the style of Google Reader.** j and k move through any list, o or Return opens the page beside it, v opens the original, s keeps a Today or feed item, m marks seen or unseen, Shift-A marks the whole list seen, c copies the link, f follows the site, e sends to the theme's destination. g then t, a, u, k, r, x or d goes to Today, all items, Unsorted, Kept, Archive, Transcripts or Duplicates; Shift-J and Shift-K step through feeds and themes; r refreshes, / searches, a follows something new. ? (or Help > Keyboard Shortcuts) shows them all.
- **Go to (⌘K).** One search field for the whole app: themes, feeds, sources and lists, Settings panes, actions such as Reload or Export, and your links by title or by their text. Type a handle or address to follow it. Arrow keys move, Return opens, Esc closes. An empty field shows the places you opened last.

## 1.2.2 - 2026-11-15

### Fixed

- Following a YouTube channel by its @handle failed in the EU, where YouTube first shows a consent page, and could pick a recommended channel's id from the page. Sift now reads the channel's own feed link.
- A podcast whose episodes all link to the show's page showed as one item. Each episode now keeps its own audio address. Sift fetches every feed once more so the fix takes effect.

## 1.2.1 - 2026-11-15

### Fixed

- A feed:// or sift:// link opened a new Sift window each time. It now goes to the window that is open.
- Following no longer shows an alert to click. A short notice fades out on its own, and several follows in a row show as one ("Following Simon Willison and 3 more").

## 1.2.0 - 2026-11-15

### Added

- **Full text from feeds, with its formatting.** When a feed carries the whole article, Sift keeps it as Markdown: paragraphs and line breaks, headings, bold and italic, links, lists, quotes and code. On the Mac, an item in Today or a feed list opens on that text, with a Text and Page switch above it. On the iPhone, tapping such a card opens the full text, and Open the original is at the end.

### Fixed

- Feed items were cut to their first 1,200 characters and lost their line breaks.

## 1.1.1 - 2026-11-15

### Changed

- **The sidebar has two chapters.** Feeds holds Today, your folders and feeds, and Follow. Library holds the Overview graph, your sources, Unsorted, Archive, Transcripts and the other upkeep lists. Each folds.

## 1.1.0 - 2026-11-15

### Added

- **Suggested from what you save.** The Follow sheet lists sites, subreddits and GitHub repositories you save from again and again, with how often ("You saved 7"), and follows one with a click.
- **Follow from anywhere.** Right-click a link and choose Follow with the site's name (or r/name, owner/repo, the YouTube channel); the button above an open page does the same. Drop a link on Feeds in the sidebar to follow it. Feeds is always in the sidebar, with a Follow row at the end.

### Changed

- **Reddit, GitHub, YouTube and the other known kinds are found from any address.** A feed:// link, a site from OPML or a pasted page address now gets the right feed (a subreddit's .rss, a repository's releases), not only what the page advertises.

## 1.0.0 - 2026-11-15

### Added

- **Follow anything with a feed.** Follow (the + in the toolbar, or Shift-Command-N) takes a site, a Substack, a subreddit (r/name), a Bluesky account (@name.bsky.social), a Mastodon account or hashtag (@user@instance, #tag@instance), a YouTube channel or playlist, a podcast (podcast: name), a GitHub repository's releases (owner/repo), Medium, Tumblr, Hacker News (hn, or hn: words), a news search (news: words) or an arXiv category (arxiv cs.AI). Sift shows which kind it recognised as you type, and a list to pick from when there are several.
- **Feeds in the sidebar.** Your folders and feeds, like a reader: each opens its recent items, without unread counts. Pause, unfollow or copy a feed from its menu.

### Changed

- **Feeds are the primary input.** With feeds, Sift opens on Today, and Feeds is first in Settings > Inputs.

## 0.9.0 - 2026-11-15

### Added

- **Today on your iPhone.** Sift writes each Today digest to iCloud Drive/Sift, and the iPhone app (in testing) shows it as cards: swipe on to pass, double-tap to keep, tap to open. Items kept on the phone arrive in Kept from Today on your Mac.
- **Subscribe links.** feed:// links, and sift://subscribe?url= with a site or feed address, open Sift and follow the feed.

## 0.8.0 - 2026-11-15

### Added

- **Today.** What your feeds offer, as a digest of about ten items at 07:00 and 17:00, at the top of the sidebar. Each item says why it is there: in several of your feeds, fits one of your themes, from a feed you often keep, or one thing different. When you have seen them all, Today says so and waits for the next digest.
- **Keep.** Press K, or Keep above the open page, and the item moves into Kept from Today and into your library, themes and search.

### Changed

- **Feed items are no longer saved links.** They show only in Today, never in your sources, themes or the unsorted count, and leave Today after three days unless you keep them. Feed items that 0.7.0 put in your archive are removed, except ones you sent or wrote a note on.

## 0.7.0 - 2026-11-15

### Added

- **Feeds.** Follow blogs, newsletters and sites with RSS, Atom or JSON Feed. Settings > Inputs > Import OPML shows every feed in your file by folder: follow all of them, or tick the ones you want. Add Feed finds a site's feed from its address. Sift checks each feed about once an hour, one site at a time, and its items work like every other link: saved text, themes, seen and search. Export OPML takes your feeds to any other reader.

## 0.6.0 - 2026-11-15

### Added

- **Seen and unseen, like read and unread mail.** Unseen links have a dot and a bold title. Opening a link marks it seen; right-click switches it. Each list has an Unseen Only switch and Mark All as Seen, and the sidebar counts unseen links per theme.
- **Seen syncs between your devices** through plain files in iCloud Drive/Sift/seen, one per device. The newest mark wins. There is no server.

## 0.5.3 - 2026-11-15

### Changed

- **Settings uses the shared house layout.** General now also has Launch at login, and About shows the GitHub star count and opens the changelog. Sift and Headroom settings work the same way.

## 0.5.2 - 2026-11-15

### Added

- **Version history in the app.** Sift > Version History shows every release, and Settings > About has the same list.

### Changed

- **One place for progress.** The bottom of the sidebar shows everything Sift is doing, each with its name and count above its bar, and says when a job waits because a site refused. The bar above the list only asks you to decide something.
- **Settings has a sidebar.** General, Inputs, Library, Outputs, Intelligence, Themes, Privacy and About, the same layout as Headroom. Updates moved to General.

## 0.5.1 - 2026-11-15

### Added

- **Updates.** Sift checks GitHub for a new version once a day and shows "Update to X" in the toolbar. Sift > Check for Updates… checks now. An update downloads, checks the checksum, Apple's notarization and the developer signature, then Sift quits and opens on the new version.
- **Transcripts.** A Transcripts list in the sidebar shows the videos and reels whose words Sift saved. Pick one and the transcript opens next to the list; the button above it switches to the video.

### Changed

- Rows no longer have a send button. Send is in the right-click menu and above the open page.

### Fixed

- Closing the page next to the list stops its video at once.

## 0.5.0 - 2026-11-15

### Added

- **Anonymous usage counts.** Once a week Sift sends one small report: the app and macOS version, which kinds of source and destination you use, which switches are on, and rough sizes such as "100-999 links". It never sends a link, title, theme name, note, account or file path, and has no install id. It is on by default; Settings > Privacy turns it off and shows the exact report. The totals are public on the Community Pulse page.

## 0.4.2 - 2026-11-15

### Fixed

- The Setup Guide no longer quits Sift when you click Continue, Back or Skip.
- When Claude Code is not signed in, Sift says how to sign in (Terminal, `claude`, then `/login`) and has a button that opens Terminal.

## 0.4.1 - 2026-11-14

### Added

- **Demo mode.** Launch with `-demo` to see Sift with made-up sample data, kept apart from your own.

### Fixed

- The graph frames itself to the window when it opens, when the window changes size and when you zoom back out of a theme.
- Sift always opens its main window after launch.

## 0.4.0 - 2026-11-14

### Added

- **Chrome.** A small Chrome extension sends your open tabs to Sift. Each profile is its own source, and Sift closes Chrome tabs itself. Brave, Edge, Arc, Vivaldi and Chromium use the same helper.
- **YouTube details.** Imported videos show their real title, channel, length and description.
- **YouTube audio.** When YouTube refuses captions, Sift can transcribe the audio on this Mac, then delete it. Videos over 90 minutes are skipped.
- **Backups.** Sift keeps hourly backups of its own files. If a file cannot be read, Sift restores the newest good backup and tells you.

### Changed

- Links show as a list only. Picking a source or theme in the sidebar opens its list; Overview stays the graph.
- The theme header is one block: name, summary, link count, where it sends, and its history.
- Starlings is one destination per workspace, named by the workspace.
- The Claude settings tab is now called Intelligence.

### Fixed

- Transcript jobs no longer stall. A refusal waits from 1 hour up to 24, even across relaunches.

## 0.3.0 - 2026-11-14

### Added

- **Your library.** Sift saves the text of every link, YouTube transcripts, Instagram images and what reels say, on this Mac, with a Library page in Settings.
- **Search** in every list, over titles, page text and transcripts, with saved searches in the sidebar.
- **Claude can read your library** through sift-mcp, a small MCP server inside Sift.
- **Send** replaces next actions: Starlings, an Obsidian folder, a Markdown file or the Reading List. A theme can have a default destination.
- **Upkeep:** duplicates with Merge All, Broken Links, and a note on any link.
- **Setup Guide** for a new Mac, from nothing to your own themes.
- **On-device model** on macOS 26 with Apple Intelligence: clear cases sorted and short summaries written on this Mac.

### Changed

- Clusters on the graph put the newest links closest to the theme. A solid dot means Sift saved the text; a ring means it has only the title.

## 0.2.0 - 2026-11-14

### Added

- First public release: Safari tabs from every device, the Reading List, Instagram Saved, X bookmarks and YouTube Takeout as sources.
- Themes that Claude finds in your own links, a graph of them, and a list per theme.
- Errands (orders, logins, carts) kept apart from what you read for interest.
- Export to Obsidian, Markdown, CSV and JSON. Signed, notarized and attested downloads.
