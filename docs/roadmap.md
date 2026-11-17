# Sift roadmap

The owner's plan (2026-11-17): "all of the above seems useful, keeping it
simple, help me plan and build towards it". One release per item, in this
order. Items marked "decision" wait for the owner.

## 1. Control

- [x] Theme dials: Stay, Lean In, Explore per theme; Sift tries a few
  sources for Lean In and Explore (1.8.3).
- [ ] "Not interested" with a reason: less of this source, less of this
  topic, seen enough of this story. Each changes one visible number.
- [ ] Snooze discovery for a week (everywhere or one theme), and "Forget
  what you learned" for one feed.
- [ ] Theme pills in the Mac sidebar (the iPhone has them).
- [ ] Loose ends: X junk text already in feed files and Today picks; X
  posts as post cards in the iPhone deck; run `export-deck.py` after the
  owner's first launch of 1.8.0 or later.

## 2. Lanes

- [ ] Custom lanes: a saved search or rule as its own stream over feed
  items.
- [ ] Settings > You on the iPhone.
- [ ] Daily time budget: Today fills to your minutes, then ends.
  Decision: it ends "rolling" Today.

## 3. On-device intelligence

- [ ] Subterms per theme: key terms computed on the Mac, sub-clusters named
  by the on-device model.
- [ ] A richer graph: creators linked by co-saves and meaning, ranked with a
  personal PageRank.
- [ ] Meaning for Next Door, and for trail starts that have no vector yet.

## 4. Discovery (decisions)

- [ ] Who follows what: anonymous counts for public feeds, published OPML
  follow lists, or Bluesky's public follow graph. Decision: which route.
- [ ] Directory searches by theme words (Bluesky starter packs, Apple
  podcasts, Hacker News domains, ooh.directory). Decision: theme words
  leave the Mac.
- [ ] Directory extras: YouTube featured channels (page scrape, decision),
  Podcast Index (key, decision), Bluesky co-follows, FeedLand OPML.
- [ ] People: YouTube channels' own links; Instagram, TikTok and X authors
  in Your Graph.

## Outside the code

- [ ] TestFlight: submit the newest build once Apple clears build 215.
