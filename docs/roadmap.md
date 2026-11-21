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
- [ ] Daily time budget. Not built: the agent's call on 2026-11-21 (owner:
  "do what u think is best"). It goes against "rolling" Today (owner,
  2026-11-15); Snooze Discovery and lanes that end keep Today finite.

## 3. On-device intelligence

- [x] Subterms per theme: TF-IDF on the Mac, shown and used in Today's
  theme fit (1.8.6). Sub-clusters named by the on-device model: built (milestone 5).
- [x] A richer graph: creators close in meaning, personal PageRank from
  the creators you follow; Lean In uses the rank (1.8.6).
- [x] Meaning for trail starts without a vector (1.8.6). Next Door by
  meaning: not built (its targets have no text of their own).

## 4. Discovery (decisions)

- [x] Who follows what: Bluesky's public follow graph (owner's choice,
  2026-11-21), in the directory (1.8.7).
- [x] Directory searches by theme words, behind an opt-in switch (owner,
  2026-11-21), 1.8.7.
- [x] Bluesky co-follows (1.8.7). Owner said no (2026-11-21) to YouTube
  featured channels and to a Podcast Index key. FeedLand OPML: not built.
- [ ] People: YouTube channels' own links; Instagram, TikTok and X authors
  in Your Graph.

## Outside the code

- [x] TestFlight: build 243 (1.8.5) submitted for beta review on 2026-11-21.

## 5. Multisocial (ADR 0001, docs/adr/0001-multisocial.md, 2026-11-21)

Open items are GitHub issues in the milestone "Multisocial (ADR 0001)",
for the factory.

- [ ] Your graph from every network: import following lists (#39).
- [ ] Network dials, trained by use (#40).
- [ ] Today themes first, with network badges (#41).
- [ ] Light actions: like and bookmark on Bluesky and Mastodon (#42).
- [ ] Watch Downloads for new exports; monthly reminder (#43).
- [ ] Co-save edges in the creator graph (#44).
- [ ] Published OPML follow lists (#45).
- [ ] Not Interested on the iPhone's Watch cards (#46).
- [ ] Docs 1:1 with the app on the website (#47).
- [x] Sub-clusters per theme, named by the on-device model; Mac chips
  filter the list, the phone shows them (1.8.8).
- [x] People: YouTube channels' own links; X, Instagram and TikTok authors
  in Your Graph (no feed) (1.8.8).
- Not built (agent's call, 2026-11-21): Next Door by meaning (its targets
  have no text); lane editing on the phone (lanes are made on the Mac).
