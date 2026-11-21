# Sift roadmap

The owner's plan (2026-11-17): "all of the above seems useful, keeping it
simple, help me plan and build towards it". One release per item, in this
order. Items marked "decision" wait for the owner.

## 1. Control

- [x] Theme dials: Stay, Lean In, Explore per theme; Sift tries a few
  sources for Lean In and Explore (1.8.3).
- [x] "Not interested" with a reason (1.8.4): less of this source, less of this
  topic, seen enough of this story. Each changes one visible number.
- [x] Snooze discovery for a week, and "Forget what you learned" for one
  feed (1.8.4). One theme: use "Less about" or the Stay dial.
- [x] Theme pills in the Mac sidebar (1.8.4).
- [x] Loose ends: X junk text in feed files and Today picks; X posts as
  post cards in the iPhone deck (1.8.5).
- [ ] Run `export-deck.py` after the owner's first launch of 1.8.0 or
  later (needs the Mac's repair to have run).

## 2. Lanes

- [x] Custom lanes: a saved rule over feed items, Mac and iPhone (1.8.5).
- [x] Settings > You on the iPhone (1.8.5).
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

- [x] TestFlight: build 243 (1.8.5) submitted for beta review on 2026-11-21.
