#!/usr/bin/env python3
"""Export a deck.json for the iOS deck prototype from the Mac's Sift data.

    python3 prototypes/ios-deck/export-deck.py            # real data
    python3 prototypes/ios-deck/export-deck.py --demo     # Sift-Demo sample
    python3 prototypes/ios-deck/export-deck.py --synth    # + synthesis cards via `claude -p`

Reads, never writes: Application Support/Sift/{search.sqlite,state.json,
previews.json,Library/*.md}. Writes deck.json to iCloud Drive/Sift/ so the
phone can open it from Files (and a copy next to this script, gitignored).
The output is personal browsing data: never commit it.
"""
import json, math, os, re, sqlite3, subprocess, sys
from pathlib import Path

DEMO = "--demo" in sys.argv
SYNTH = "--synth" in sys.argv
SUPPORT = Path.home() / "Library/Application Support" / ("Sift-Demo" if DEMO else "Sift")
ICLOUD = Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/Sift"
PER_THEME = 40          # items per theme in the export
NEIGHBOURS = 6
FULL_TEXT = 8000        # characters of full text per item

def front_matter(path):
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError:
        return {}, ""
    meta = {}
    if raw.startswith("---"):
        end = raw.find("\n---\n", 3)
        if end > 0:
            for line in raw[3:end].splitlines():
                if ":" in line:
                    k, v = line.split(":", 1)
                    meta[k.strip()] = v.strip().strip('"')
            raw = raw[end + 5:]
    return meta, raw.strip()

def split_transcript(body):
    m = re.search(r"^## Transcript.*$", body, re.M)
    if not m:
        return body, ""
    return body[:m.start()].strip(), body[m.end():].strip()

def passage(text):
    """The first paragraph that reads like prose, about 400 characters."""
    for para in re.split(r"\n\s*\n", text):
        p = " ".join(para.split())
        if len(p) > 160 and not p.startswith(("#", "http", "|", "--")) and p.count(" ") > 20:
            return p[:420] + ("…" if len(p) > 420 else "")
    return ""

def hue(index, count):
    n = max(count, 1)
    stride = max(1, round(n * 0.382))
    while math.gcd(stride, n) != 1:
        stride += 1
    return (28 + ((index * stride) % n) * 360 / n) % 360

def main():
    db = sqlite3.connect(f"file:{SUPPORT / 'search.sqlite'}?mode=ro", uri=True)
    state = json.loads((SUPPORT / "state.json").read_text())
    previews = json.loads((SUPPORT / "previews.json").read_text()) if (SUPPORT / "previews.json").exists() else {}
    themes = sorted(p["name"] for p in state.get("extraProjects", []) if p.get("isTheme"))
    summaries = {r[0]: r[1] for r in db.execute("select name, summary from themes")}

    rows = db.execute("select url, title, theme, source, kind, saved, file, also, summary from links where theme is not null and theme != ''").fetchall()
    by_theme = {}
    for r in rows:
        by_theme.setdefault(r[2], []).append(r)

    items, chosen = [], set()
    for t in themes:
        # Best material first: a transcript, then a summary, then saved text.
        loaded = []
        for r in by_theme.get(t, []):
            meta, body = front_matter(SUPPORT / "Library" / r[6]) if r[6] else ({}, "")
            text, transcript = split_transcript(body)
            score = 4 * bool(transcript) + 2 * bool(r[8]) + bool(len(text) > 400)
            loaded.append((score, r, meta, text, transcript))
        loaded.sort(key=lambda x: (-x[0], x[1][5] or ""), reverse=False)
        for _, r, meta, text, transcript in loaded[:PER_THEME]:
            url, title, theme, source, kind, saved, file, also, summary = r
            p = previews.get(url, {})
            items.append({
                "id": url, "url": url, "title": title or p.get("title") or url,
                "theme": theme, "kind": kind or "page", "site": meta.get("site") or p.get("site") or "",
                "author": meta.get("author"), "saved": saved,
                "duration": int(meta["duration"]) if meta.get("duration", "").isdigit() else None,
                "summary": summary or meta.get("summary") or "",
                "passage": passage(text) or (p.get("text") or "")[:420],
                "transcript": transcript[:1200],
                "text": (transcript if transcript and len(text) < 400 else text)[:FULL_TEXT],
                # Only web images: a file URL is a Mac path the phone cannot read.
                "image": p.get("imageURL") if str(p.get("imageURL") or "").startswith("http") else None,
                "also": json.loads(also) if also and also.startswith("[") else [],
                "neighbours": [],
            })
            chosen.add(url)

    # Neighbours: a full-text match on the title's longest words, then the
    # same theme. Only items that are in the export.
    index = {it["id"]: it for it in items}
    for it in items:
        words = [w for w in re.findall(r"[\w']{5,}", it["title"].lower())][:6]
        found = []
        if words:
            q = " OR ".join('"%s"' % w.replace('"', "") for w in words)
            try:
                for (u,) in db.execute("select url from fts where fts match ? order by bm25(fts) limit 30", (q,)):
                    if u != it["id"] and u in index and u not in found:
                        found.append(u)
            except sqlite3.Error:
                pass
        same = [u for u in found if index[u]["theme"] == it["theme"]]
        other = [u for u in found if index[u]["theme"] != it["theme"]]
        rest = [o["id"] for o in items if o["theme"] == it["theme"] and o["id"] != it["id"] and o["id"] not in found]
        it["neighbours"] = (same + rest[:NEIGHBOURS] + other)[:NEIGHBOURS]

    deck_themes = [{"name": t, "summary": summaries.get(t) or "", "hue": hue(i, len(themes)),
                    "count": sum(1 for it in items if it["theme"] == t)} for i, t in enumerate(themes)]

    synthesis = []
    if SYNTH:
        for t in deck_themes:
            pick = [it for it in items if it["theme"] == t["name"] and it["summary"]][:6]
            if len(pick) < 3:
                continue
            prompt = ("Here are saved links from one theme of my reading, each with a summary. In 3 short sentences, say what they add up to and where they disagree. Plain English, no preamble.\n\n"
                      + "\n\n".join(f"- {p['title']}: {p['summary']}" for p in pick))
            try:
                out = subprocess.run(["claude", "-p", "--model", "sonnet", "--tools", "", "--no-session-persistence", prompt],
                                     capture_output=True, text=True, timeout=180, cwd="/tmp").stdout.strip()
            except Exception as e:
                print("synthesis skipped:", t["name"], e, file=sys.stderr)
                continue
            if out:
                synthesis.append({"theme": t["name"], "text": out, "items": [p["id"] for p in pick]})
                print("synthesis:", t["name"], file=sys.stderr)

    deck = {"schema": 1, "demo": DEMO, "themes": deck_themes, "items": items, "synthesis": synthesis}
    data = json.dumps(deck, ensure_ascii=False)
    # Demo output is made-up sample data: it ships in the app as the deck
    # it opens with. Real output stays out of git.
    here = Path(__file__).parent / ("App/sample-deck.json" if DEMO else "deck.json")
    here.write_text(data)
    if not DEMO:
        ICLOUD.mkdir(parents=True, exist_ok=True)
        (ICLOUD / "deck.json").write_text(data)
    print(f"{len(items)} items, {len(deck_themes)} themes, {len(synthesis)} synthesis cards, {len(data)//1024} KB", file=sys.stderr)
    print(f"wrote {here}" + ("" if DEMO else f" and {ICLOUD / 'deck.json'}"), file=sys.stderr)

if __name__ == "__main__":
    main()
