#!/usr/bin/env python3
"""Writes the demo mode sample data into Demo/ (see Sift/Demo/Demo.swift).

Run from the repo root: python3 scripts/demo/make-data.py
The content is in scripts/demo/content.py. The thumbnails are drawn by
scripts/demo/make-images.swift, which this script runs at the end.
Standard library only. The output is deterministic.
"""

import datetime as dt
import hashlib
import json
import os
import plistlib
import random
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import content as C  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "Demo")
NOW = dt.datetime(2026, 11, 14, 9, 0, tzinfo=dt.timezone.utc)
REF = dt.datetime(2001, 1, 1, tzinfo=dt.timezone.utc)
URL_BASE = "{{DEMO_URL}}"
PATH_BASE = "{{DEMO_PATH}}"

IPHONE, MAC = "demo-iphone", "demo-studio-mac"
YOUTUBE_ID = "demo-youtube"
SOURCE_KEY = {"I": "tabs:" + IPHONE, "M": "tabs:" + MAC, "R": "reading-list", "G": "instagram",
              "X": "x", "Y": "import:" + YOUTUBE_ID}
PALETTE = ["#3B7DD8", "#D9822B", "#2E9E6A", "#7A5AC8", "#C8475B", "#1F8FA3", "#8C9A2A", "#B5577E", "#5C6BC0"]
BUCKET_COLOR = "#8A8F98"

rng = random.Random(14)


def iso(d):
    return d.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def ref(d):
    return (d - REF).total_seconds()


def key16(url):
    return hashlib.sha1(url.encode()).hexdigest()[:16]


def slug(title):
    s = re.sub(r"[^a-z0-9]+", "-", title.lower().replace("'", "")).strip("-")
    return s[:70].strip("-")


def host(url):
    h = re.sub(r"^https?://", "", url).split("/")[0].split("?")[0].split("#")[0]
    return h[4:] if h.startswith("www.") else h


# MARK: Build the link list

links = []  # dicts: url, src, theme, title, preview, site, ...
counters = {"G": 0, "X": 0, "Y": 0}


def make(src, site, title, preview, theme):
    if src == "G":
        counters["G"] += 1
        url = f"https://www.instagram.com/p/SiftDemo{counters['G']:02d}/"
    elif src == "X":
        counters["X"] += 1
        url = f"https://x.com/{site}/status/{1900000000000000000 + counters['X']}"
    elif src == "Y":
        counters["Y"] += 1
        url = f"https://www.youtube.com/watch?v=siftdemo{counters['Y']:03d}"
    elif site.startswith("wiki:"):
        url = "https://en.wikipedia.org/wiki/" + site[5:]
    elif "/" in site:
        url = "https://" + site
    else:
        url = f"https://{site}/{slug(title)}"
    return {"url": url, "src": src, "site": site, "title": title, "preview": preview, "theme": theme}


by_theme = {}
for t in C.THEMES:
    by_theme[t["name"]] = [make(*l, t["name"]) for l in t["links"]]
for bucket, items in C.BUCKETS.items():
    by_theme[bucket] = [make(*l, bucket) for l in items]

# Interleave themes so recency mixes them, then date every link.
order = []
groups = [list(v) for v in by_theme.values()]
while any(groups):
    for g in groups:
        if g:
            order.append(g.pop(0))
for i, l in enumerate(order):
    l["date"] = NOW - dt.timedelta(hours=6 * i + rng.randint(0, 5), minutes=rng.randint(0, 59))
    links.append(l)

# Duplicates: the variant is an iPhone tab with the same content.
for theme, idx, variant in C.DUPLICATES:
    orig = by_theme[theme][idx]
    d = dict(orig, url=variant, src="I", date=orig["date"] + dt.timedelta(days=9))
    links.append(d)

# Archived links: seen on the iPhone, closed since.
archived = []
for n, (theme, site, title, preview) in enumerate(C.ARCHIVED):
    a = make("I", site, title, preview, theme)
    a["date"] = NOW - dt.timedelta(days=60 + 3 * n)
    a["archived"] = NOW - dt.timedelta(days=20 + 2 * n)
    archived.append(a)

everything = links + archived
urls = [l["url"] for l in everything]
assert len(urls) == len(set(urls)), "duplicate URL in sample data"

# MARK: Checks

ERRAND_WORDS = ["/order", "/account", "/checkout", "/cart", "/basket", "/login", "/signin", "/signup", "/register",
                "/billing", "/invoice", "/settings", "/dashboard", "/admin", "/track", "/booking", "/reservation",
                "/subscription", "/payment", "/compose", "/inbox", "/edit"]


def all_text():
    yield from (t["summary"] for t in C.THEMES)
    for l in everything:
        yield l["title"]; yield l["preview"]
    for _, _, text in C.ARTICLES:
        yield text
    for *_, text in C.TRANSCRIPTS:
        yield text
    for *_, note in C.NOTES:
        yield note


for s in all_text():
    assert "—" not in s and "–" not in s, f"dash in: {s}"
    assert "“" not in s and "”" not in s, f"curly quote in: {s}"
for l in everything:
    if l["theme"] not in C.BUCKETS:
        path = "/" + l["url"].split("://", 1)[1].split("/", 1)[-1]
        assert not any(w in path for w in ERRAND_WORDS), f"theme link looks like an errand: {l['url']}"

# MARK: Images

theme_names = sorted(t["name"] for t in C.THEMES)
color = {name: PALETTE[i % len(PALETTE)] for i, name in enumerate(theme_names)}
glyph = {t["name"]: t["glyph"] for t in C.THEMES}
images = []  # manifest for make-images.swift


def image_for(l):
    name = key16(l["url"]) + ".png"
    tint = color.get(l["theme"], BUCKET_COLOR)
    letter = (l["title"] if l["src"] != "G" else l["site"].split(".")[1])[:1].upper()
    shape = "square" if l["src"] == "G" else ("video" if l["src"] == "Y" else "wide")
    images.append({"file": name, "color": tint, "letter": letter, "shape": shape, "seed": int(key16(l["url"])[:6], 16)})
    return f"{URL_BASE}/Images/{name}"


avatars = {}
for handle in sorted({l["site"] for l in everything if l["src"] == "X"}):
    file = f"avatar-{handle}.png"
    theme = next(l["theme"] for l in everything if l["src"] == "X" and l["site"] == handle)
    images.append({"file": file, "color": color.get(theme, BUCKET_COLOR), "letter": handle[5:6].upper(),
                   "shape": "avatar", "seed": int(hashlib.sha1(handle.encode()).hexdigest()[:6], 16)})
    avatars[handle] = f"{URL_BASE}/Images/{file}"

# MARK: Write

shutil.rmtree(OUT, ignore_errors=True)
for sub in ["Images", "Library", "Imports/instagram-demo/your_instagram_activity/saved", "iCloud Drive/Sift"]:
    os.makedirs(os.path.join(OUT, sub), exist_ok=True)


def write_json(rel, value, pretty=True):
    with open(os.path.join(OUT, rel), "w") as f:
        json.dump(value, f, indent=2 if pretty else None, sort_keys=True, ensure_ascii=False)
        f.write("\n")


ig_collection = {}
for name, accounts in C.INSTAGRAM_COLLECTIONS.items():
    for a in accounts:
        ig_collection.setdefault(a, name)

# Previews and archive records.
previews, archive = {}, {}
igname = {l["site"]: l["title"] for l in everything if l["src"] == "G"}
for l in everything:
    if l["src"] == "X":
        p = {"title": C.X_NAMES[l["site"]], "text": l["title"], "site": "x.com", "avatarURL": avatars[l["site"]]}
        title = f"{C.X_NAMES[l['site']]} on X: {l['title'][:120]}"
        image = avatars[l["site"]]
    elif l["src"] == "G":
        coll = ig_collection.get(l["site"])
        text = (f"Saved in {coll}. " if coll else "") + l["preview"]
        image = image_for(l)
        p = {"title": l["title"], "text": text, "site": "instagram.com", "imageURL": image}
        title = l["title"]
    else:
        image = image_for(l)
        site = "youtube.com" if l["src"] == "Y" else host(l["url"])
        p = {"title": l["title"], "text": l["preview"], "site": site, "imageURL": image}
        title = l["title"]
    p["fetched"] = ref(l["date"])
    previews[l["url"]] = p
    l["display"] = title
    r = {"url": l["url"], "title": title, "source": SOURCE_KEY[l["src"]], "use": "",
         "previewText": p["text"], "imageURL": image, "firstSeen": iso(l["date"]),
         "lastSeen": iso(l.get("archived", NOW)), "theme": l["theme"]}
    if "archived" in l:
        r["archived"] = iso(l["archived"])
    archive[l["url"]] = r

for theme, idx, note in C.NOTES:
    archive[by_theme[theme][idx]["url"]]["takeaway"] = note

# Library: page text, posts, videos, transcripts, gone pages.
library = {}
articles = {(t, i): text for t, i, text in C.ARTICLES}
transcripts = {(t, i): (secs, text) for t, i, secs, text in C.TRANSCRIPTS}
gone = {by_theme[t][i]["url"] for t, i in C.GONE} | {a["url"] for a in archived[:2]}


def yaml(s):
    return json.dumps(s, ensure_ascii=False)


for theme, items in by_theme.items():
    if theme in C.BUCKETS:
        continue
    for i, l in enumerate(items):
        url = l["url"]
        captured = l["date"] + dt.timedelta(hours=1)
        if url in gone:
            library[url] = {"file": "", "captured": iso(captured), "words": 0, "kind": "page", "status": "gone"}
            continue
        entry = None
        if l["src"] in ("X", "G"):
            kind, text = "post", l["title"] if l["src"] == "X" else previews[url]["text"]
        elif l["src"] == "Y":
            kind = "video"
            text = f"Video by {l['site']}.\n\n{l['preview']}"
        elif (theme, i) in articles:
            kind, text = "article", articles[(theme, i)]
        elif i % 3 != 2:
            kind, text = "article", l["preview"]
        else:
            continue
        duration = None
        transcript = None
        if l["src"] == "Y":
            duration = transcripts.get((theme, i), (rng.randint(300, 2400), None))[0]
            if (theme, i) in transcripts:
                text += "\n\n## Transcript\n\n" + transcripts[(theme, i)][1]
                transcript = True
            else:
                transcript = False
        file = key16(url) + ".md"
        front = ["---", f"url: {yaml(url)}", f"title: {yaml(l['display'])}", f"site: {yaml(previews[url]['site'])}",
                 f"kind: {kind}"]
        if l["src"] == "Y":
            front.append(f"author: {yaml(l['site'])}")
        if duration:
            front.append(f"duration: {duration}")
        front += [f"theme: {yaml(theme)}", f"source: {yaml(SOURCE_KEY[l['src']])}", f"captured: {iso(captured)}",
                  f"words: {len(text.split())}", "---", "", text, ""]
        with open(os.path.join(OUT, "Library", file), "w") as f:
            f.write("\n".join(front))
        entry = {"file": file, "captured": iso(captured), "words": len(text.split()), "kind": kind, "status": "ok"}
        if duration:
            entry["duration"] = duration
        if transcript is not None:
            entry["transcript"] = transcript
        library[url] = entry
for a in archived[:2]:
    library[a["url"]] = {"file": "", "captured": iso(a["date"]), "words": 0, "kind": "page", "status": "gone"}
write_json("Library/index.json", library, pretty=False)
write_json("previews.json", previews, pretty=False)
write_json("archive.json", archive, pretty=False)

# Assignments.
also = {}
for theme, idx, other in C.CONNECTIONS:
    also.setdefault(by_theme[theme][idx]["url"], []).append(other)
assignments = {}
for n, l in enumerate(everything):
    a = {"project": l["theme"], "use": "", "manual": n % 23 == 0, "also": also.get(l["url"], []),
         "sortedBy": "device" if n % 4 == 0 else "claude"}
    assignments[l["url"]] = a

# Themes with history.
projects = []
for t in C.THEMES:
    c = len(by_theme[t["name"]])
    counts = {"a": max(3, c - 7), "b": c - 3, "c": c}
    p = {"name": t["name"], "summary": t["summary"], "isTheme": True, "destination": "", "notes": "",
         "history": [f"{d}: {line.format(**counts)}" for d, line in C.HISTORY]}
    if t["name"] in C.SEND_TO:
        p["sendTo"] = C.SEND_TO[t["name"]]
    projects.append(p)
projects[6]["history"].insert(1, "2026-09-21: continues Note Apps")

destinations = [
    {"id": "demo-starlings", "kind": "starlings", "name": "Starlings: Demo", "detail": "demo.starlings.example",
     "config": {"origin": "https://demo.starlings.example"}},
    {"id": "demo-obsidian", "kind": "obsidian", "name": "Field Notes", "detail": "~/Documents/Field Notes/Inbox",
     "config": {"folder": PATH_BASE + "/Field Notes/Inbox"}},
]
sent = {}
for dest, groups_ in C.SENT.items():
    for theme, idxs in groups_:
        for i in idxs:
            l = by_theme[theme][i]
            sent.setdefault(l["url"], []).append({"destination": dest, "date": ref(l["date"] + dt.timedelta(days=2))})

close_queue = [l["url"] for l in by_theme["drop"] if l["src"] == "I"]

state = {
    "assignments": assignments,
    "extraProjects": projects,
    "deviceID": "all-sources",
    "backend": "claudeCode",
    "closeQueue": close_queue,
    "exportTargets": {},
    "importedSources": [{"id": YOUTUBE_ID, "name": "YouTube Watch Later", "path": PATH_BASE + "/Imports/youtube-watch-later.json",
                         "added": ref(NOW - dt.timedelta(days=40))}],
    "autoCapture": True, "youtubeTranscripts": True, "instagramImages": True, "reelTranscripts": True,
    "findConnections": True, "youtubeAudio": True, "closeAfterSend": True,
    "mergedInto": {},
    "savedSearches": C.SAVED_SEARCHES,
    "destinations": destinations,
    "sent": sent,
    "blockedUntil": {}, "backoffHours": {},
    "xClientID": "demo-client-id", "xUserID": "1", "xUsername": "sift_demo", "xSyndication": False,
    "instagramExportPath": PATH_BASE + "/Imports/instagram-demo",
    "localFirstPass": True, "localSorting": True, "localSummaries": True,
    "chromeProfileNames": {},
}
write_json("state.json", state)
with open(os.path.join(OUT, "iCloud Drive/Sift/close.txt"), "w") as f:
    f.write("\n".join(close_queue) + "\n")

# Safari: the iCloud Tabs database, the shape CloudTabsReader reads.
db = sqlite3.connect(os.path.join(OUT, "CloudTabs.db"))
db.execute("CREATE TABLE cloud_tab_devices (device_uuid TEXT PRIMARY KEY, device_name TEXT)")
db.execute("CREATE TABLE cloud_tabs (tab_uuid TEXT PRIMARY KEY, device_uuid TEXT, url TEXT, title TEXT, last_viewed_time REAL)")
db.executemany("INSERT INTO cloud_tab_devices VALUES (?, ?)", [(IPHONE, "iPhone"), (MAC, "Studio Mac")])
for n, l in enumerate(x for x in links if x["src"] in ("I", "M")):
    db.execute("INSERT INTO cloud_tabs VALUES (?, ?, ?, ?, ?)",
               (f"demo-tab-{n:03d}", IPHONE if l["src"] == "I" else MAC, l["url"], l["title"], ref(l["date"])))
db.commit()
db.execute("VACUUM")
db.close()

# Reading List: Safari's Bookmarks.plist, the part ReadingListReader reads.
reading = [{"URLString": l["url"], "URIDictionary": {"title": l["title"]},
            "ReadingList": {"DateAdded": l["date"].replace(tzinfo=None), "PreviewText": l["preview"]}}
           for l in sorted((x for x in links if x["src"] == "R"), key=lambda x: x["date"], reverse=True)]
with open(os.path.join(OUT, "Bookmarks.plist"), "wb") as f:
    plistlib.dump({"Children": [{"Title": "com.apple.ReadingList", "Children": reading}]}, f, fmt=plistlib.FMT_XML)

# Instagram Saved: the JSON export's saved_posts.json and saved_collections.json.
ig = [l for l in links if l["src"] == "G"]
posts = [{"timestamp": int(l["date"].timestamp()), "label_values": [
    {"label": "URL", "href": l["url"]},
    {"label": "Caption", "value": l["preview"]},
    {"title": "Owner", "dict": [{"dict": [{"label": "Name", "value": l["title"]}, {"label": "Username", "value": l["site"]}]}]},
]} for l in ig]
collections = [{"label_values": [
    {"label": "Name", "value": name},
    {"title": "Media", "dict": [{"dict": [{"label": "URL", "href": l["url"]}]} for l in ig if l["site"] in accounts]},
]} for name, accounts in C.INSTAGRAM_COLLECTIONS.items()]
saved = "Imports/instagram-demo/your_instagram_activity/saved/"
write_json(saved + "saved_posts.json", posts)
write_json(saved + "saved_collections.json", collections)

# YouTube Watch Later: a JSON link import.
yt = [{"url": l["url"], "title": l["title"], "note": l["preview"], "folder": "Watch Later", "created_at": iso(l["date"])}
      for l in links if l["src"] == "Y"]
write_json("Imports/youtube-watch-later.json", {"items": yt})

# X Bookmarks: posts as XStore keeps them, and the bookmark order.
xposts, xorder = {}, []
for l in sorted((x for x in links if x["src"] == "X"), key=lambda x: x["date"], reverse=True):
    pid = l["url"].rsplit("/", 1)[1]
    xposts[pid] = {"id": pid, "text": l["title"], "created": iso(l["date"]),
                   "author": {"id": "demo-" + l["site"], "name": C.X_NAMES[l["site"]], "username": l["site"], "avatar": avatars[l["site"]]},
                   "media": [], "links": [], "mentions": [], "tags": [], "edited": False,
                   "fetched": iso(NOW), "removed": False}
    xorder.append(pid)
write_json("x-posts.json", xposts)
write_json("x-bookmarks.json", xorder)

# Thumbnails.
with tempfile.TemporaryDirectory() as tmp:
    manifest = os.path.join(tmp, "images.json")
    with open(manifest, "w") as f:
        json.dump(images, f)
    subprocess.run(["swift", os.path.join(ROOT, "scripts/demo/make-images.swift"), manifest, os.path.join(OUT, "Images")], check=True)

count = {s: sum(1 for l in links if l["src"] == s) for s in "IMRGXY"}
print(f"{len(links)} links ({count}), {len(archived)} archived, {len(library)} library entries, {len(images)} images")
