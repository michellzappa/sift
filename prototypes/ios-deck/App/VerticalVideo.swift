import SwiftUI
import WebKit

/// A vertical video (YouTube Short, Instagram reel, TikTok). Owner rule
/// (issue #30): transcript first, tap to play. Changed 2026-11-16 (owner):
/// in Today's Watch tab a YouTube video plays muted while its card is on
/// screen (`autoplay`, switch in Log: "watch.autoplay"); TikTok and
/// Instagram still wait for a tap.
enum VerticalVideo: Hashable, Sendable {
    case youTube(String)
    /// `path` is "reel" or "p", as in the item's URL.
    case instagram(path: String, id: String)
    case tikTok(String)
    /// A Vimeo video (found in a page).
    case vimeo(String)
    /// A video file (og:video .mp4, .m3u8): played in a <video> element.
    case file(String)
    /// A player page made to be embedded (twitter:player, og:video as a page).
    case embed(String)

    /// Plays muted on its own: YouTube, Vimeo and files take a mute switch.
    var autoplays: Bool {
        switch self {
        case .youTube, .vimeo, .file: true
        default: false
        }
    }

    /// The vertical video in the item, if it is one. `vertical` is the Mac's
    /// flag on a Today pick (true for YouTube Shorts).
    static func detect(_ item: Item, vertical: Bool? = nil) -> VerticalVideo? {
        let url = item.url
        if vertical == true || url.contains("/shorts/"), let id = TodayPick.youTubeID(url) {
            return .youTube(id)
        }
        if let m = match(url, #"instagram\.com/(reels?|p)/([\w-]+)"#) {
            let path = m[0].hasPrefix("reel") ? "reel" : "p"
            // Instagram's export lists most saved reels as /p/ addresses, so
            // every post gets the embed: it plays a reel and shows a photo
            // post alike. The poster shows first either way.
            return .instagram(path: path, id: m[1])
        }
        if let m = match(url, #"tiktok\.com/@[^/?#]+/video/(\d+)"#) {
            return .tikTok(m[0])
        }
        return nil
    }

    /// The capture groups of the first match.
    private static func match(_ s: String, _ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1..<m.numberOfRanges).compactMap { Range(m.range(at: $0), in: s).map { String(s[$0]) } }
    }

    /// The posters to try, in order, after the item's own picture.
    var posters: [String] {
        if case .youTube(let id) = self {
            return ["https://i.ytimg.com/vi/\(id)/hq720.jpg", "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"]
        }
        return []
    }

    var label: String {
        switch self {
        case .youTube: "YouTube"
        case .instagram: "Instagram"
        case .tikTok: "TikTok"
        case .vimeo: "Vimeo"
        case .file, .embed: "Video"
        }
    }
}

/// The full-card layout for a vertical video: the poster fills the card,
/// title and site sit at the bottom over a dark gradient, and a large play
/// button is in the middle. A tap loads the player inline. The player
/// unloads when the card goes off screen or `active` becomes false.
struct VerticalVideoCard<Accessory: View>: View {
    let item: Item
    let video: VerticalVideo
    /// False when another card is the current one: the player stops.
    var active = true
    /// A double-tap on the poster (Today: keep). Nil: no double-tap.
    var doubleTap: (() -> Void)? = nil
    /// Called when the user starts the player.
    var played: () -> Void = {}
    /// Opens the transcript or summary in the reader.
    let text: () -> Void
    /// A 16:9 video (a normal YouTube video) in the same full card.
    var wide = false
    /// Plays muted while the card is the current one (YouTube, Vimeo, files).
    var autoplay = false
    /// Why it is here: Today's reason line, or the theme in the Library.
    var reason: String? = nil
    @ViewBuilder var accessory: () -> Accessory
    @State private var playing = false
    /// True while the player was started by autoplay: it is muted.
    @State private var muted = false

    var body: some View {
        Group {
            if wide {
                // A wide video sits at the top; what it is and why fills the
                // space below (owner, 2026-11-16).
                VStack(spacing: 0) {
                    ZStack {
                        Color.black
                        if playing {
                            VerticalPlayer(video: video, muted: muted, wide: true).id(muted)
                        } else {
                            poster
                        }
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipped()
                    details(summaryLines: 6)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                    Spacer(minLength: 56)
                }
                .background(Color.black)
            } else {
                ZStack {
                    Color.black
                    if playing {
                        VerticalPlayer(video: video, muted: muted)
                            .id(muted)
                            .aspectRatio(9 / 16, contentMode: .fit)
                    } else {
                        poster
                    }
                }
                .overlay(alignment: .bottom) {
                    if !playing { caption }
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 8) {
                Button(action: text) {
                    Label("Text", systemImage: item.transcript.isEmpty ? "doc.plaintext" : "captions.bubble")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                if playing {
                    Button { playing = false } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .overlay(alignment: .bottomTrailing) { accessory().padding(12) }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .onDisappear { playing = false }
        .onChange(of: active) { _, now in if now { autostart() } else { playing = false } }
        .task(id: active) { autostart() }
    }

    /// The poster with the play button. The gestures sit on the poster only,
    /// so the player's own controls get every tap once it loads.
    private var poster: some View {
        PosterImage(item: item, extra: video.posters)
            .overlay {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.white, .black.opacity(0.4))
                    .shadow(radius: 8)
            }
            .contentShape(Rectangle())
            .gesture(TapGesture(count: 2).onEnded { doubleTap?() }
                .exclusively(before: TapGesture().onEnded { start() }))
    }

    /// Over a vertical video's poster: what it is and why, on a gradient.
    private var caption: some View {
        details(summaryLines: 2)
            .padding(.horizontal, 16)
            .padding(.top, 60)
            // Room for the pills below the text.
            .padding(.bottom, 56)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
    }

    /// Why it is here, the title, channel, age and length, then the summary
    /// (or the start of the transcript).
    private func details(summaryLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reason, !reason.isEmpty {
                Label(reason, systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.yellow)
                    .lineLimit(1)
            }
            Text(item.title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(3)
            Text(byline)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            if !blurb.isEmpty {
                Text(blurb)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(summaryLines)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }

    /// "Channel · 2 days ago · 12 min".
    private var byline: String {
        let who = item.author.flatMap { $0.isEmpty ? nil : $0 } ?? (item.site.isEmpty ? video.label : item.site)
        let when = (item.published ?? item.saved).flatMap(Self.date)?.formatted(.relative(presentation: .named))
        return [who, when, item.length].compactMap { $0 }.joined(separator: " · ")
    }

    private var blurb: String {
        let summary = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? item.excerpt : summary
    }

    private static func date(_ s: String) -> Date? {
        if let d = try? Date(s, strategy: .iso8601) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }

    private func start() {
        guard !playing || muted else { return }
        muted = false
        playing = true
        played()
    }

    /// Starts the player muted when the card settles on screen. A tap on the
    /// poster plays with sound; autoplay is not a "play" signal.
    private func autostart() {
        guard autoplay, active, !playing, video.autoplays,
              UserDefaults.standard.object(forKey: "watch.autoplay") as? Bool ?? true else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard active, !playing else { return }
            muted = true
            playing = true
        }
    }
}

/// The poster: the local image from the Deck folder, else the item's web
/// image, else each of `extra` in turn (a YouTube thumbnail that is missing
/// falls through to the next size).
private struct PosterImage: View {
    @Environment(Store.self) private var store
    let item: Item
    let extra: [String]
    @State private var index = 0

    private var candidates: [String] {
        // An automatic YouTube thumbnail from the Today pick is 4:3; the
        // larger poster list comes first then.
        var list: [String] = []
        if let image = item.image, !(image.contains("i.ytimg.com") && !extra.isEmpty) { list.append(image) }
        list += extra
        return list
    }

    var body: some View {
        let tint = store.color(item.theme)
        Rectangle().fill(tint.opacity(0.25))
            .overlay {
                if let local = store.localImage(item), let image = UIImage(contentsOfFile: local.path(percentEncoded: false)) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if index < candidates.count, let url = URL(string: candidates[index]) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        case .failure: Color.clear.onAppear { index += 1 }
                        default: Color.clear
                        }
                    }
                    .id(index)
                } else {
                    Image(systemName: "play.rectangle").font(.system(size: 40)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .clipped()
    }
}

/// The inline player in a web view: plays inline, needs a tap in the player
/// to start: it is made only after the tap on the poster, then plays at once
/// (one tap), and unloads the page when it goes away, so
/// the sound stops at once. A wide player goes full screen when the phone
/// turns (`FullscreenPlayer`).
struct VerticalPlayer: UIViewRepresentable {
    let video: VerticalVideo
    /// Autoplay: start without sound. The player's own button turns it on.
    var muted = false
    /// A 16:9 video: turning the phone shows it full screen.
    var wide = false

    final class Coordinator { var web: WKWebView? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // The player is made only after the user taps the poster, so it may
        // start at once: one tap plays (owner, 2026-11-15). Nothing plays
        // before that tap.
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.scrollView.isScrollEnabled = false
        web.isOpaque = false
        web.backgroundColor = .black
        switch video {
        case .youTube(let id):
            let src = "https://www.youtube-nocookie.com/embed/\(id)?playsinline=1&rel=0&loop=1&playlist=\(id)&autoplay=1&enablejsapi=1" + (muted ? "&mute=1" : "")
            let html = """
            <html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;background:#000}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style></head>
            <body><iframe src="\(src)" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe></body></html>
            """
            web.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
        case .instagram(let path, let id):
            if let url = URL(string: "https://www.instagram.com/\(path)/\(id)/embed/") { web.load(URLRequest(url: url)) }
        case .tikTok(let id):
            if let url = URL(string: "https://www.tiktok.com/embed/v2/\(id)?autoplay=1") { web.load(URLRequest(url: url)) }
        case .vimeo(let id):
            let src = "https://player.vimeo.com/video/\(id)?autoplay=1&playsinline=1" + (muted ? "&muted=1" : "")
            let html = """
            <html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;background:#000}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style></head>
            <body><iframe src="\(src)" allow="autoplay; fullscreen; picture-in-picture" allowfullscreen></iframe></body></html>
            """
            web.loadHTMLString(html, baseURL: URL(string: "https://player.vimeo.com"))
        case .file(let src):
            let safe = src.replacingOccurrences(of: "\"", with: "%22").replacingOccurrences(of: "<", with: "%3C")
            let html = """
            <html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;background:#000}video{position:absolute;inset:0;width:100%;height:100%}</style></head>
            <body><video src="\(safe)" playsinline autoplay controls loop \(muted ? "muted" : "")></video></body></html>
            """
            web.loadHTMLString(html, baseURL: nil)
        case .embed(let src):
            if let url = URL(string: src) { web.load(URLRequest(url: url)) }
        }
        let home = UIView()
        home.backgroundColor = .black
        web.frame = home.bounds
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        home.addSubview(web)
        context.coordinator.web = web
        if wide { FullscreenPlayer.shared.attach(web, home: home) }
        return home
    }

    func updateUIView(_ view: UIView, context: Context) {}

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        guard let web = coordinator.web else { return }
        FullscreenPlayer.shared.detach(web)
        web.pauseAllMediaPlayback()
        web.loadHTMLString("", baseURL: nil)
    }
}

/// Turn the phone and the wide video on screen fills it (owner, 2026-11-16).
/// The app stays portrait: the player's web view moves into the window,
/// turned a quarter, so the list under it never lays out again and the
/// card keeps its place. Turning back puts it in its card. Going full screen
/// turns the sound on: turning the phone is the choice to watch.
@MainActor final class FullscreenPlayer {
    static let shared = FullscreenPlayer()
    private weak var web: WKWebView?
    private weak var home: UIView?
    private var observer: NSObjectProtocol?
    private var isOn = false

    func attach(_ web: WKWebView, home: UIView) {
        if let old = self.web, old !== web { leave(animated: false) }
        self.web = web
        self.home = home
        if observer == nil {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            observer = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { FullscreenPlayer.shared.turned() }
            }
        }
        // Already sideways when the player starts: wait for it to be in a window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.turned() }
    }

    func detach(_ web: WKWebView) {
        guard web === self.web else { return }
        leave(animated: false)
        web.removeFromSuperview()
        self.web = nil
        self.home = nil
    }

    private func turned() {
        switch UIDevice.current.orientation {
        case .landscapeLeft: enter(angle: .pi / 2)
        case .landscapeRight: enter(angle: -.pi / 2)
        case .portrait: leave(animated: true)
        default: break
        }
    }

    private func enter(angle: CGFloat) {
        guard let web, let home, let window = home.window else { return }
        if web.superview !== window {
            let frame = home.convert(home.bounds, to: window)
            web.removeFromSuperview()
            web.autoresizingMask = []
            web.transform = .identity
            web.frame = frame
            window.addSubview(web)
        }
        let b = window.bounds
        UIView.animate(withDuration: 0.3) {
            web.transform = CGAffineTransform(rotationAngle: angle)
            web.bounds = CGRect(x: 0, y: 0, width: b.height, height: b.width)
            web.center = CGPoint(x: b.midX, y: b.midY)
        }
        if !isOn {
            isOn = true
            // YouTube's iframe takes commands by postMessage (enablejsapi=1).
            web.evaluateJavaScript("""
            (function(){var f=document.querySelector('iframe');if(!f)return;
            ['unMute','playVideo'].forEach(function(c){f.contentWindow.postMessage(JSON.stringify({event:'command',func:c,args:[]}),'*')});})();
            (function(){var f=document.querySelector('iframe');if(f){f.contentWindow.postMessage(JSON.stringify({method:'setVolume',value:1}),'*');f.contentWindow.postMessage(JSON.stringify({method:'setMuted',value:false}),'*')}
            var v=document.querySelector('video');if(v){v.muted=false;v.play()}})()
            """)
        }
    }

    private func leave(animated: Bool) {
        guard isOn, let web else { isOn = false; return }
        isOn = false
        guard let home, let window = web.superview else { return }
        let target = home.convert(home.bounds, to: window)
        let back = {
            web.removeFromSuperview()
            web.transform = .identity
            web.frame = home.bounds
            web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            home.addSubview(web)
        }
        guard animated else { back(); return }
        UIView.animate(withDuration: 0.3, animations: {
            web.transform = .identity
            web.frame = target
        }, completion: { _ in back() })
    }
}
