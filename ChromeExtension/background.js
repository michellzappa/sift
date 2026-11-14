// Sift for Chrome. Sends this profile's open tabs (URL, title, window, last
// access, pinned) to Sift on this Mac through native messaging, and closes
// the tabs Sift marked to close. It reads no page content and makes no
// network requests. The host is sift-chrome inside Sift.app.
//
// Messages, extension to host:
//   { type: "snapshot", version: 1, install, browser, extensionVersion,
//     tabs: [{ url, title, windowId, lastAccessed, pinned }] }
// Host to extension, in reply to each snapshot:
//   { type: "close", urls: [...] }   (URLs open in this snapshot that Sift
//                                     marked to close; often empty)
//   { type: "error", message }

const HOST = "app.sift.chrome";
const DEBOUNCE_MS = 3000;
// An open native port keeps the service worker alive, so this timer runs.
const RESEND_MS = 60 * 1000;

let port = null;
let debounce = null;
let installID = null;

// One random id per profile, kept in IndexedDB (no storage permission).
// Sift uses it to tell profiles apart.
function idb(mode, run) {
  return new Promise((resolve, reject) => {
    const open = indexedDB.open("sift", 1);
    open.onupgradeneeded = () => open.result.createObjectStore("meta");
    open.onerror = () => reject(open.error);
    open.onsuccess = () => {
      const tx = open.result.transaction("meta", mode);
      const req = run(tx.objectStore("meta"));
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    };
  });
}

async function getInstallID() {
  if (installID) return installID;
  let id = await idb("readonly", (s) => s.get("install"));
  if (!id) {
    id = crypto.randomUUID();
    await idb("readwrite", (s) => s.put(id, "install"));
  }
  installID = id;
  return id;
}

// The browser's own brand ("Google Chrome", "Brave", "Microsoft Edge").
// The host prefers the name of the app that started it.
function browserName() {
  const brands = (navigator.userAgentData && navigator.userAgentData.brands) || [];
  const named = brands.map((b) => b.brand).filter((b) => !/Not.?A.?Brand|^Chromium$/i.test(b));
  return named[0] || "Chromium";
}

function connect() {
  if (port) return port;
  try {
    port = chrome.runtime.connectNative(HOST);
  } catch (e) {
    port = null;
    return null;
  }
  port.onMessage.addListener(onHostMessage);
  port.onDisconnect.addListener(() => {
    // Not installed, or Sift was removed. The next tab event tries again.
    void chrome.runtime.lastError;
    port = null;
  });
  return port;
}

async function sendSnapshot() {
  const p = connect();
  if (!p) return;
  const tabs = await chrome.tabs.query({});
  const list = [];
  for (const t of tabs) {
    const url = t.url || t.pendingUrl || "";
    if (t.incognito || !/^https?:\/\//i.test(url)) continue;
    list.push({
      url,
      title: t.title || "",
      windowId: t.windowId,
      lastAccessed: typeof t.lastAccessed === "number" ? Math.round(t.lastAccessed) : null,
      pinned: !!t.pinned,
    });
  }
  try {
    p.postMessage({
      type: "snapshot",
      version: 1,
      install: await getInstallID(),
      browser: browserName(),
      extensionVersion: chrome.runtime.getManifest().version,
      tabs: list,
    });
  } catch (e) {
    port = null;
  }
}

async function onHostMessage(message) {
  if (!message || message.type !== "close" || !Array.isArray(message.urls) || message.urls.length === 0) return;
  const close = new Set(message.urls.filter((u) => typeof u === "string"));
  const tabs = await chrome.tabs.query({});
  const ids = tabs.filter((t) => !t.incognito && close.has(t.url)).map((t) => t.id);
  if (ids.length > 0) await chrome.tabs.remove(ids);
}

function schedule() {
  clearTimeout(debounce);
  debounce = setTimeout(sendSnapshot, DEBOUNCE_MS);
}

chrome.tabs.onCreated.addListener(schedule);
chrome.tabs.onRemoved.addListener(schedule);
chrome.tabs.onReplaced.addListener(schedule);
chrome.tabs.onUpdated.addListener((_id, change) => {
  if (change.url !== undefined || change.title !== undefined || change.pinned !== undefined) schedule();
});
chrome.runtime.onStartup.addListener(schedule);
chrome.runtime.onInstalled.addListener(schedule);

setInterval(sendSnapshot, RESEND_MS);
schedule();
