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
3. In the app: Log > Import deck.json…, pick it from iCloud Drive/Sift.
4. Use it for a few days. Log > Share log.jsonl sends the decisions back.

## What it has

- **Deck:** seven cards across themes (or one theme from the top-right menu).
  Right keep, left let go, up send, down later (two per deck), tap to read.
  The end card counts what you did; another deck is a quiet button.
- **Stream:** one thread per theme. Down goes deeper: the start item, then
  its neighbours (full-text match on the title, then the same theme), a
  synthesis card after five, a time marker every six, and a card when the
  thread runs dry. Sideways changes thread, only when you swipe.
- **Log:** the week's numbers, the deck file, the decision log.

`App/sample-deck.json` is the export of Sift's demo data (`--demo`), so it is
safe to commit.
