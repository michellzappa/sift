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

- [ ] Your graph from every network: import whom you follow from each
  network's export (YouTube Takeout, Instagram, TikTok, X archive) and
  directly from Bluesky and Mastodon; each account a People place,
  followed where a feed exists.
- [ ] Network dials (More, Normal, Less, Off) trained by use: the learned
  share shown beside each; the network in "Why this is here".
- [ ] Today themes first: grouped and coloured by theme, network badges,
  Mac and iPhone.
- [ ] Light actions: Bluesky and Mastodon sign-in for like and bookmark;
  "Open in <app>" for the rest.
- [ ] Watch Downloads for new exports; a monthly reminder per stale network.
- [x] Sub-clusters per theme, named by the on-device model (1.8.8).
- [ ] Your graph from every network: import who you follow from each
  network's own data export (YouTube Takeout subscriptions, Instagram
  following, TikTok Following, X archive following) and directly from
  Bluesky and Mastodon. Each account becomes a People place; follow where a
  feed exists; nothing leaves the Mac.
- [ ] Network mix: one visible control per network (More, Normal, Less,
  Off) for its share of Today, in "Why this is here" and Algorithm.
- [x] Sub-clusters per theme, named by the on-device model (Mac chips filter the list; phone shows them).
- [ ] Co-save edges in the creator graph.
- [ ] People: YouTube channels' own links; Instagram, TikTok and X authors
  in Your Graph.
- [ ] Published OPML follow lists (FeedLand and others) as a "who follows
  what" source.
- [ ] Not Interested on the phone's Watch cards.
- Not built (agent's call, 2026-11-21): Next Door by meaning (its targets
  have no text); lane editing on the phone (lanes are made on the Mac).
