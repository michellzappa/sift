# ADR 0002: Discovery and virality

- Status: accepted
- Date: 2026-11-21
- Decided by: the owner ("yes yes a little"), after the agent's proposal
- Builds on: ADR 0001 (multisocial reader; data only from exports and
  public sources; no logins to Instagram, TikTok or X)

## Context

The owner asked how Sift can show discovery, what people share on the
networks, and virality. On Instagram, TikTok and X, virality cannot be
seen from outside without a login: no public trends, no feeds. Most reels
and TikToks spread through direct messages, not through the feed. Open
networks (Bluesky, Mastodon) and link sites (Hacker News, Reddit,
Techmeme) publish what is spreading.

## Decisions

1. **Shared with you.** Sift reads the links friends sent the person in
   direct messages from the Instagram and TikTok exports: the link and the
   sender's name only, never the message text. They form a saved source,
   "Shared with you". A link that several friends sent ranks higher. It
   stays on the Mac like everything else.

2. **Share sheet.** An iPhone share extension, "Send to Sift", takes a post
   or link from any app at once, between exports. It writes to the Sift
   folder in iCloud Drive; the Mac adds it like any other saved link.

3. **Spreading among people you follow.** While Sift runs, it may keep one
   open connection to Bluesky's public live stream (Jetstream). It keeps
   only posts from the accounts the person follows and the accounts those
   follow (two steps), counts the links they share, and measures how fast.
   A pick then says "Spreading: 7 people you follow shared it in 2 hours".
   Nothing about the person goes to the stream beyond the account ids Sift
   asks it to filter on.

4. **Trending in the open.** Public trend sources feed a "Trending" lane
   and a few places in Today: Mastodon trending links and tags (from a
   few large instances), Bluesky trending topics, the Hacker News front
   page, Reddit popular and Techmeme.

5. **Virality is a visible dial.** One dial: Off, A little (the default),
   More. Popularity never ranks on its own: it is one factor of the score,
   named in "Why this is here" with its numbers ("7 shares in 2 hours",
   "trending on Mastodon"). Off removes every viral pick.

## Consequences

- Instagram, TikTok and X virality reaches Sift only through what friends
  send the person (exports, the share sheet), never network-wide.
- Reading direct-message exports touches other people's messages: Sift
  reads links and sender names only, keeps them on the Mac, and says so
  where the source is turned on (off until the person turns it on).
- One long-lived connection (Bluesky Jetstream) while Sift runs; it stops
  when Sift quits or when the dial is Off.
- The Today score gains a virality factor with the dial's weight; the
  Algorithm pane, How Today Works and the website docs explain it.
