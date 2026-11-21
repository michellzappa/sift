# ADR 0001: Sift becomes a multisocial reader

- Status: accepted
- Date: 2026-11-21
- Decided by: the owner, in an interview with the agent (three rounds of
  questions, same day)

## Context

Sift already reads what a person saves on many networks (Safari, Reading
List, Instagram Saved, TikTok favourites, X bookmarks, YouTube) and what
they follow as feeds. It ranks a finite Today, explains every pick, and has
controls: theme dials, Not Interested, Snooze, lanes. The owner asked for
"a multisocial app that leans on existing SNS data, but lets the user have
control and visibility of their algo". This ADR records what that means.

## Decisions

1. **Same app, same name.** The multisocial reader is Sift's next phase,
   not a new app. The name stays Sift.

2. **For heavy readers first.** People who save a lot across networks and
   accept some setup (exports, feeds). Mainstream polish comes later.

3. **The daily loop stays open.** Design toward all three: one stream that
   can replace the apps, a digest after the apps, and review of saves.
   Do not lock the product to one of them yet.

4. **Data only from exports and public sources.** Sift reads the data a
   person downloads from each network (Instagram and TikTok exports, the X
   archive, YouTube Takeout) and public sources (RSS, Bluesky and Mastodon
   public APIs, oEmbed). Sift never logs in to Instagram, TikTok or X and
   never uses browser cookies. The north star holds: nothing about the
   library goes to a Sift server.

5. **Light actions, only on open networks.** Sift may like and bookmark or
   save back on Bluesky and Mastodon, after the person signs in there with
   OAuth. These are the only logins Sift holds. For every other network, a
   button opens the post in that network's app.

6. **Control: dials and switches, trained by use.** The main controls are
   a few visible dials (per network: More, Normal, Less, Off; per theme:
   Stay, Lean In, Explore; Snooze). Behind them, Sift learns from use, the
   way TikTok and Instagram do: what you open, keep, finish and skip moves
   each network's and each theme's weight. Each dial shows what Sift
   learned next to what you set.

7. **Visibility through themes, numbers on request.** "Themes are more fun
   than numbers": Today, Algorithm and the dials show what is happening in
   terms of themes (which themes fill your Today, which grow, which you
   steer). Every number stays one click away ("Why this is here"), never in
   front.

8. **Today is themes first.** The stream is grouped and coloured by theme;
   each item carries a small network badge. The network is a detail, the
   theme is the headline.

9. **Algorithms are not shared.** No export or import of a person's
   algorithm. Settings stay personal (they already live in state.json).

10. **Freshness for export-only networks.** Sift watches the Downloads
    folder and picks up a new Instagram, TikTok, X or YouTube export when it
    lands. Once a month it reminds the person which network is stale, with
    the steps to export it.

11. **Networks first:** YouTube, Instagram and TikTok, X, Bluesky and
    Mastodon, all in this phase.

## What this means to build (roadmap milestone 5)

- Import whom you follow from every network's export (YouTube Takeout
  subscriptions, Instagram following, TikTok following, X archive following
  and bookmarks) and directly from Bluesky and Mastodon; each account
  becomes a People place, followed as a feed where one exists.
- A network dial per network (More, Normal, Less, Off) with the share Sift
  learned from use shown beside it; "Why this is here" names the network.
- Today grouped by theme, with network badges, on the Mac and the iPhone.
- Bluesky and Mastodon sign-in (OAuth) for like and bookmark; "Open in
  <app>" everywhere else.
- Watch Downloads for new exports; a monthly reminder per stale network.

## Consequences

- Instagram, TikTok and X posts reach Sift only as fast as the person
  exports them; their new posts never reach Today. Sift says so plainly.
- The only credentials Sift holds are Bluesky and Mastodon tokens, in the
  keychain, with the smallest scopes that allow like and bookmark.
- Learning by use needs signals per network; the ranking gains one factor
  (the network weight), shown with the others.
- Not decided yet: which daily loop leads (decision 3). Revisit after the
  owner has used the themes-first Today for a while.
