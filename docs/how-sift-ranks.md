# How Sift ranks

Today is the one ranked list in Sift. It runs on your Mac. It makes no
Claude call and sends nothing to a server. The only model it uses is
Apple's on-device embeddings (NaturalLanguage), for closeness in meaning.

This page explains the ranking in words first, then gives every number.
The numbers come from the code: `Sift/Engine/Today.swift`,
`Sift/Engine/NetworkDial.swift`, `Sift/Engine/Dials.swift`,
`Sift/Engine/Meaning.swift` and `Sift/Feeds/Signals.swift`. Sift shows the
same numbers in three places:

- "Why this is here", under every pick: the rule that gave the pick its
  place and each part of its score.
- Settings > Algorithm: the formula, today's picks by score, the network
  dials, what Sift learned per feed, Your Graph and where AI is used.
- How Today Works (the ? in Today's toolbar, or Help > How Today Works):
  the rules in plain words and each feed's standing.

## In words

### What can come in

Today takes items from the feeds you follow. It does not take your saved
links: those are your Library. An item can come in when it is at most three
days old and you have not seen or kept it. Items from Don't Miss feeds can
be up to 14 days old. When a mode has too few picks, older items (up to 14
days) can fill it.

Some items never come in. A feed set to Not in Today has none, and a
network set to Off has none. An item that you marked "seen enough of this
story" stays out for a week, and so does any item that shares three or more
words with it. When one person posts the same thing on two platforms (a
Bluesky post that only points to their new video), Sift shows the item and
leaves out the pointer.

### The order of places

1. Don't Miss items, newest first. They have no score and no limit.
2. Items from sources that Sift is trying for a theme (see Theme dials,
   below).
3. Hot items: a link that two or more of your feeds carry. More feeds go
   higher.
4. The rest, by score.
5. In each mode (Scan, Watch, Read): older items if the mode has fewer than
   five picks, then one "New to you" pick and one "Something different"
   pick.

### The score

A new item scores higher than an old one. It loses about half its weight in
a day. A rare post counts more than the 30th post of a busy feed. A feed
that you read often lifts its items, by up to 80%, and a feed that you skip
lowers them.

On top of that, an item gets a lift when:

- it shares words with one of your themes, or it is close in meaning to the
  theme;
- it comes from a creator you follow in Your Graph (more saves give a
  bigger lift);
- other feeds of yours link to it in their posts this week;
- you followed its feed from the directory less than 30 days ago;
- two or more of your feeds carry the same link.

Then the network dial multiplies the score. A network that you open and
keep more than the others gets a little more. A network that you skip gets
a little less.

### Fair shares

A Normal feed can have three unseen picks in Today at a time. When you see
one, the next one can come in. A busy feed (more than five posts a day)
is Best Only unless you choose otherwise. A Best Only feed gets one pick,
and only when the item has a strong signal: it is Hot, fits a theme, is
linked by your other feeds, comes from a creator with five or more saves,
or comes from a feed that you read often.

The network dial changes the share. More gives each feed five places (two
for Best Only). Less gives each feed one place and no extra slots.

### Modes

Scan holds headlines and posts. Watch holds videos. Read holds articles,
blogs and newsletters. Each mode should have five picks. When a mode has
fewer, Sift adds unseen items of that mode up to 14 days old, best score
first. It first keeps to each feed's share. If that is not enough, it goes
past the share, so one video channel can fill Watch on a quiet day. A Less
network never goes past its share.

Each mode also gets two extra picks:

- "New to you": the best item from a Normal feed that Sift knows little
  about (fewer than three signals) and that has no pick yet.
- "Something different": a random item from a feed that has no pick yet.
  Sift takes it from outside the top ten when it can, and not from a Best
  Only feed.

### Linked by your feeds

Sift reads the links inside your feeds' posts of the last week. It skips
links to the post's own site, link aggregators, shops, sponsors, tip jars
and media files. An item that other feeds of yours link to gets a lift, and
its reason says "Linked by" with their names. A link that two or more of
your feeds point to, but that no feed carries, gets a place of its own. At
most three such picks show at a time. One person counts once, and a person
never counts as "Linked by" for their own work.

### What Sift learns from you

Every time you keep, open, play or read a Today pick, its feed gets a
little more weight. A quick skip on the iPhone takes a little away, and
Not Interested ("less from this source") takes more away. Old signals fade:
after 30 days a signal counts about a third. Signals from your iPhone count
the same as signals from the Mac.

Sift learns per network the same way. It compares how much you do with one
network's picks against all networks. A network needs at least five picks
before it can move, and it moves slowly until it has many more.

### Your controls

- Feed priority, in How Today Works or a feed's menu: Auto, Don't Miss,
  Normal, Best Only or Not in Today.
- Network dials, in Today's toolbar, Settings > Algorithm or the iPhone's
  Settings: More, Normal, Less or Off for each network (YouTube, Podcasts,
  Bluesky, Mastodon, Reddit, Hacker News, blogs and newsletters, Google
  News, GitHub, arXiv).
- Theme dials, in the theme's header, its sidebar menu or the iPhone's
  theme page: Stay, Lean In or Explore. Lean In doubles the theme's lift and
  tries up to two creators you save from there but do not follow. Explore
  tries up to three sources one step out, from Next Door, the directory and
  Farther. A tried source is not a follow. Its items say "Trying for
  <theme>". It goes after 14 days unless you follow it, and a keep gives it
  14 more days. Sift tries at most 12 sources at a time and never tries one
  twice.
- Not Interested, in each pick's menu: less from this source, less about
  this theme (30 days), or seen enough of this story (7 days).
- Snooze Discovery, in Today's toolbar: for a week, only your feeds' own
  picks. It turns off the "Linked by" places, "New to you", "Something
  different" and tried sources. The "Linked by" lift on your feeds' own
  items stays.
- Forget What Sift Learned, in a feed's menu: the feed's older signals no
  longer count.

### Today keeps going

Today has no fixed size and no fixed time. After each feed check, follow or
visit, new picks go on top in rank order. Picks already there keep their
place until they leave the window (three days, 14 for Don't Miss items and
for picks that filled a mode). Only one "Something different" pick per mode
shows at a time. Rebuild Today, a priority change or a network dial change
builds the list again from nothing.

### Themes first

Today shows its picks in sections by theme, each in the theme's colour,
with a small badge for the network. A pick's theme is the theme it fits, or
else the top theme of the Your Graph creator that its feed follows.
Sections go by their best pick's score. Inside a section the picks keep
their rank order. Picks with no theme go into "Other", last. Group by Theme
in the toolbar turns this off. Grouping changes only the display, not the
score.

### Not in the ranking

- Claude. Today never calls it.
- Popularity on Instagram, TikTok or X. Sift cannot see it without a login
  and never logs in there.
- Virality. ADR 0002 plans a virality dial (Off, A little, More) with
  "Spreading" and "Trending" picks. It is not built yet (issues #48 to
  #52). See [Decision: discovery and virality](adr/0002-discovery-and-virality.md).

## The numbers

### Window and shares

| Name | Value | Code |
| --- | --- | --- |
| Window for new items | 3 days | `TodayBuilder.windowDays` |
| Don't Miss window | 14 days | `mustWindowDays` |
| Fill window | 14 days | `fillWindowDays` |
| Unseen picks per Normal feed | 3 | `perFeed` |
| Unseen picks per Best Only feed | 1 | |
| Picks each mode should have | 5 | `perMode` |
| Auto makes a feed Best Only above | 5 posts a day | `FeedPriority.busyPerDay` |
| "Something different" avoids the top | 10 | `size` |
| "New to you" needs fewer than | 3 signals for the feed | |

Posts a day is the number of items in the last 14 days divided by the days
since the oldest of them (at least one day). A feed that holds only its
last 30 items still reads as busy.

### The score

    score = (fresh × volume × reading + graph + vouched + theme + linked + hot) × network

| Part | Formula | Notes |
| --- | --- | --- |
| fresh | exp(−hours / 36) | 1 when new, 0.5 after about 25 hours |
| volume | 1 / √(max(posts a day, 0.3)) | at most about 1.83 |
| reading | 1 + 0.8 × affinity | affinity is −1 to 1 |
| graph | min(0.12 × log2(1 + saves), 0.6) | only for a creator you follow; 14 saves give about 0.47 |
| vouched | min(0.1 × log2(1 + vouchers), 0.3) | a feed followed from the directory, first 30 days |
| theme (words) | 0.15 × min(shared words, 4) | needs 3 or more shared words; at most 0.6 |
| theme (meaning) | min(2 × (cos − 0.35), 0.6) | needs cos ≥ 0.45 and a lead of 0.04 over the next theme |
| linked | min(0.3 × feeds, 0.9) | your other feeds that link to it this week |
| hot | 0.6 × (feeds − 1) | feeds that carry the same link |
| network | dial × (1 + 0.3 × learned) | dial: More 1.5, Normal 1, Less 0.5 |

Theme words are words of five letters or more, without a short list of
common ones, in the item's title and summary. Sift compares them with the
theme's name, summary and terms (the words that set the theme apart). The
theme part takes the larger of the word fit and the meaning fit, never
both. Meaning is the cosine between the item's vector and the theme's
centre (the mean of its links' vectors, after the corpus mean is taken
off).

The theme dial and Not Interested change the theme part:

| Case | Effect |
| --- | --- |
| Lean In | the theme part counts twice |
| Theme muted (Less about this theme) | the theme part is removed and 0.5 is taken off, for 30 days |

A negative score (a muted theme) is divided by the network factor, not
multiplied, so Less still pushes it down.

A "Linked by" pick of its own scores fresh + linked, times the network
factor of its host. Its title is the link's text when that has 12
characters or more and is not a generic word ("here", "this", "via" and
similar), else the address.

### Strong signals

Best Only feeds need a strong signal. Any of these makes an item strong:

- Hot (2 or more feeds carry the link)
- a theme fit, by words or by meaning
- linked by another of your feeds
- a followed creator with 5 or more saves
- feed affinity above 0.4

When the item's theme is muted, only affinity above 0.4 makes it strong.

### Affinity

    affinity = tanh(sum(weight × exp(−days / 30)) / 5)

| Signal | Weight |
| --- | --- |
| Keep | +3 |
| Open, play, mark unseen | +1 |
| Time on screen (phone) | 0.05 per second, at most +1 |
| Quick skip (under 1.5 seconds, phone) | −0.4 |
| Less from this source | −1.5 |

The reason line says "You often read <feed>" when affinity is above 0.4 or
you kept two or more of the feed's items.

### Network learning

Over the last 30 days, Sift collects the picks you saw per network: items
with any signal, plus Today picks you saw without a signal (scrolled past
in Scan). Each item's weight is the sum of its signals, with the same
weights and fading as above.

    learned = tanh(network mean − mean over all networks) × n / (n + 10)

Here n is the number of items for the network. Learned is 0 when n is under
5. The network factor is dial × (1 + 0.3 × learned), so learning moves a
network by less than 30% either way.

| Dial | Factor | Places per feed | Extra slots | Fill past the share |
| --- | --- | --- | --- | --- |
| More | 1.5 | 5 (Best Only 2) | yes | yes |
| Normal | 1 | 3 (Best Only 1) | yes | yes |
| Less | 0.5 | 1 | no | no |
| Off | 0 | none, Don't Miss included | no | no |

A feed's network comes from its provider. Web, Substack, Medium, Tumblr and
unknown providers are "Blogs and newsletters". A "Linked by" pick takes its
network from its host.

### Theme dials

| Dial | Theme lift | Tried sources | Places for tried items |
| --- | --- | --- | --- |
| Stay | × 1 | 0 | 0 |
| Lean In | × 2 | up to 2, from Your Graph creators you save from in the theme | up to 2 per theme |
| Explore | × 1 | up to 3, from Next Door, the directory and Farther | up to 3 per theme |

A tried source lasts 14 days (`Trials.days`); a keep adds 14 days. At most
12 tried sources at a time (`Trials.maxTotal`). Each tried source gets one
place at a time. Items from the 3-day window come first, then older ones up
to 14 days.

### Not Interested and Snooze

| Choice | Effect | How long |
| --- | --- | --- |
| Less from this source | a −1.5 signal on the feed | fades like any signal |
| Less about this theme | theme part removed, −0.5 | 30 days |
| Seen enough of this story | items with 3 or more of its words, or its address, stay out | 7 days |
| Snooze Discovery | no "Linked by" places, "New to you", "Something different" or tried sources | 7 days |

### Linked by

| Name | Value |
| --- | --- |
| Posts that count | the last 7 days |
| Lift per linking feed | +0.3, at most +0.9 |
| Feeds needed for a place of its own | 2 (one person counts once) |
| Places of its own at a time | at most 3 |
| Newest link must be | within the 3-day window |

## Other rankings

These lists are not Today, but they rank too. All of them run on your Mac.

- Trails (More Like This, the T key): up to 20 unseen items from your saves
  and the last 14 days of your feeds. Same creator +3, same theme +1.5,
  then the larger of 0.6 per shared word (at most 5 words) and
  6 × (cos − 0.25) (at most 3). An item needs 1.8 to join. At most 4 per
  creator.
- Your Graph: each save counts 0.5^(age / 90 days). A creator needs 2
  saves to show.
- Next Door: creators outside your graph that 2 or more of yours link to.
  Each linking creator adds 1 + log(1 + its own score).
- The directory: each voucher adds 1 plus a weight. The small web counts
  1.3 times. A description close to one of your themes in meaning
  multiplies the score by 1 + cos. Sift keeps at most 12 per group, only
  feeds that posted in the last 30 days, and builds the list once a week.
- Lanes: no score. A lane shows the last 14 days of matching feed items,
  unseen first, at most 60.

## When the ranking changes

This page must change in the same commit as the ranking. So must How Today
Works, Settings > Algorithm and "Why this is here" (`Views/HowTodayWorks.swift`,
`Views/AlgorithmSettings.swift`, `Views/PickWhyView.swift`).
