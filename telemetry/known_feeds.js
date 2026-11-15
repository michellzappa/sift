// Well-known public feeds that a Mac may report by id (docs/telemetry.md,
// issue #33). The Mac downloads this list from /v1/feeds/known and reports
// only the ids of its follows that match an entry. Any other feed never
// leaves the Mac. Add only large, public publications and sources, never a
// person's small blog. Ids are stable: never reuse or rename one.
//
// `match` entries are "host" or "host/path", lowercase, without "www.".
// A host matches itself and its subdomains; a path matches itself and
// anything below it.
export const KNOWN_FEEDS_VERSION = 1;

export const KNOWN_FEEDS = [
  { id: "nytimes", name: "The New York Times", match: ["nytimes.com"] },
  { id: "bbc", name: "BBC News", match: ["bbc.co.uk", "bbci.co.uk", "bbc.com"] },
  { id: "guardian", name: "The Guardian", match: ["theguardian.com"] },
  { id: "economist", name: "The Economist", match: ["economist.com"] },
  { id: "ft", name: "Financial Times", match: ["ft.com"] },
  { id: "reuters", name: "Reuters", match: ["reuters.com"] },
  { id: "npr", name: "NPR", match: ["npr.org"] },
  { id: "atlantic", name: "The Atlantic", match: ["theatlantic.com"] },
  { id: "newyorker", name: "The New Yorker", match: ["newyorker.com"] },
  { id: "bloomberg", name: "Bloomberg", match: ["bloomberg.com"] },
  { id: "verge", name: "The Verge", match: ["theverge.com"] },
  { id: "arstechnica", name: "Ars Technica", match: ["arstechnica.com"] },
  { id: "wired", name: "Wired", match: ["wired.com"] },
  { id: "techcrunch", name: "TechCrunch", match: ["techcrunch.com"] },
  { id: "platformer", name: "Platformer", match: ["platformer.news"] },
  { id: "stratechery", name: "Stratechery", match: ["stratechery.com"] },
  { id: "daringfireball", name: "Daring Fireball", match: ["daringfireball.net"] },
  { id: "sixcolors", name: "Six Colors", match: ["sixcolors.com"] },
  { id: "9to5mac", name: "9to5Mac", match: ["9to5mac.com"] },
  { id: "macrumors", name: "MacRumors", match: ["macrumors.com"] },
  { id: "apple-newsroom", name: "Apple Newsroom", match: ["apple.com/newsroom"] },
  { id: "swift", name: "Swift.org", match: ["swift.org"] },
  { id: "github-blog", name: "The GitHub Blog", match: ["github.blog"] },
  { id: "cloudflare-blog", name: "The Cloudflare Blog", match: ["blog.cloudflare.com"] },
  { id: "lwn", name: "LWN.net", match: ["lwn.net"] },
  { id: "hackernews", name: "Hacker News front page", match: ["news.ycombinator.com", "hnrss.org/frontpage"] },
  { id: "simonwillison", name: "Simon Willison", match: ["simonwillison.net"] },
  { id: "anthropic", name: "Anthropic", match: ["anthropic.com"] },
  { id: "openai", name: "OpenAI", match: ["openai.com"] },
  { id: "astralcodexten", name: "Astral Codex Ten", match: ["astralcodexten.com", "astralcodexten.substack.com"] },
  { id: "marginalrevolution", name: "Marginal Revolution", match: ["marginalrevolution.com"] },
  { id: "lesswrong", name: "LessWrong", match: ["lesswrong.com"] },
  { id: "paulgraham", name: "Paul Graham", match: ["paulgraham.com"] },
  { id: "kottke", name: "kottke.org", match: ["kottke.org"] },
  { id: "xkcd", name: "xkcd", match: ["xkcd.com"] },
  { id: "quanta", name: "Quanta Magazine", match: ["quantamagazine.org"] },
  { id: "nature", name: "Nature", match: ["nature.com"] },
  { id: "gargron", name: "Eugen Rochko (Mastodon)", match: ["mastodon.social/@gargron"] },
  { id: "r-programming", name: "r/programming", match: ["reddit.com/r/programming"] },
  { id: "r-technology", name: "r/technology", match: ["reddit.com/r/technology"] },
  { id: "r-worldnews", name: "r/worldnews", match: ["reddit.com/r/worldnews"] },
  { id: "r-science", name: "r/science", match: ["reddit.com/r/science"] },
  { id: "r-apple", name: "r/apple", match: ["reddit.com/r/apple"] },
  { id: "r-machinelearning", name: "r/MachineLearning", match: ["reddit.com/r/machinelearning"] },
];

export const KNOWN_FEED_IDS = new Set(KNOWN_FEEDS.map((feed) => feed.id));
