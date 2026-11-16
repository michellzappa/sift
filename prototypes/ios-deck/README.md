# Sift deck prototype (iOS)

Throwaway. It answers four questions with your own library on your phone:

1. Do swipe directions as decisions feel natural?
2. Is seven the right deck size?
3. Does the stream feel deeper as you scroll down, with real neighbours?
4. Do synthesis cards add anything?

It reads a `deck.json` and writes only its own `log.jsonl`. Nothing reaches
Sift, Starlings or any server. Delete this folder once the answers are in.

## Use it

1. On the Mac: `python3 prototypes/ios-deck/export-deck.py` (add `--synth`
   for one synthesis card per theme through your `claude -p`). It writes
   `deck.json` to iCloud Drive/Sift. The file is your browsing data and is
   gitignored.
2. Open `SiftDeck.xcodeproj` after `xcodegen generate` in this folder, pick
   your iPhone, Run. The app opens on made-up sample data.
3. In the app: Lists > Log (top right) > Import deck.json…, pick it from iCloud Drive/Sift.
4. Use it for a few days. Lists > Log > Share log.jsonl sends the decisions back.

## What it has

- **Scan, Watch, Read (tabs):** today's picks from the Mac, split by how
  you take them in, the same modes as the Mac's switch. The Mac writes
  each pick's `mode` into today.json. Scan is a list of headlines and
  posts; Watch is the full-screen video cards; Read is long texts with the
  reading time. Tap opens the reader and counts as seen, swipe right
  keeps, swipe left switches seen. Library and Lists follow; Log is the
  button at the top right of Lists.
- **Deck:** seven cards across themes (or one theme from the top-right menu).
  Right keep, left let go, up send, down later (two per deck), tap to read.
  The end card counts what you did; another deck is a quiet button.
- **Stream:** one thread per theme. Down goes deeper: the start item, then
  its neighbours (full-text match on the title, then the same theme), a
  synthesis card after five, a time marker every six, and a card when the
  thread runs dry. Sideways changes thread, only when you swipe.
- **Log:** the week's numbers, the deck file, the decision log.
- **Vertical video:** a YouTube Short (a `/shorts/` URL or `vertical: true`
  on a Today pick), an Instagram reel and a TikTok get a full-card layout:
  the poster fills the card, the title sits at the bottom, a large play
  button in the middle. A tap loads the player inline in the card with
  sound. In Today's Watch tab a YouTube video (Short or normal, the normal
  one in a 16:9 player) plays muted while its card is on screen; Log has
  the switch "Autoplay videos, muted". TikTok and Instagram wait for a tap. Swiping on
  unloads it. The Text pill opens the transcript or summary. In Today,
  double-tap and the Keep pill still keep. Turn the phone while a wide video plays and
  it fills the screen with sound; turn back and it returns to its card.
  Library in the Watch tab shows your saved videos as the same player
  cards (Instagram reels and TikTok on a tap).
- **Signals:** what you do with Today picks goes to
  `iCloud Drive/Sift/signals/iphone-<id>.json` for the Mac's ranking:
  dwell (seconds on screen, 1.5 s or more), skip, open, keep, unseen and
  play. A copy stays in the app's Documents (`signals-here.json`).

`App/sample-deck.json` is the export of Sift's demo data (`--demo`), so it is
safe to commit.
