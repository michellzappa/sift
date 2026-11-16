import SwiftUI
import AVKit
import WebKit

/// Instagram and TikTok in the system player, not their embed pages (owner,
/// 2026-11-16). Their embed pages carry the video file but no API gives it:
/// `ClipResolver` loads the embed off screen (no cookies kept: a
/// non-persistent store), reads the <video> element's address or the
/// `video_url` / `playAddr` in the page, and hands it, with the page's
/// cookies and referer, to AVPlayer. Addresses expire, so they live in
/// memory only. When nothing is found the card shows the embed as before.
@MainActor final class ClipResolver {
    static let shared = ClipResolver()

    struct Clip: @unchecked Sendable {
        let url: URL
        let cookies: [HTTPCookie]
        let referer: String
    }

    static let agent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private var cache: [VerticalVideo: Clip?] = [:]
    private var running: [VerticalVideo: Task<Clip?, Never>] = [:]

    func clip(for video: VerticalVideo) async -> Clip? {
        if let hit = cache[video] { return hit }
        if let task = running[video] { return await task.value }
        let task = Task { await self.resolve(video) }
        running[video] = task
        let clip = await task.value
        running[video] = nil
        cache.updateValue(clip, forKey: video)
        return clip
    }

    private func resolve(_ video: VerticalVideo) async -> Clip? {
        let page: URL?
        let referer: String
        switch video {
        case .instagram(let path, let id):
            page = URL(string: "https://www.instagram.com/\(path)/\(id)/embed/")
            referer = "https://www.instagram.com/"
        case .tikTok(let id):
            page = URL(string: "https://www.tiktok.com/embed/v2/\(id)")
            referer = "https://www.tiktok.com/"
        default:
            return nil
        }
        guard let page, let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return nil }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        // Nothing plays or sounds in the hidden page.
        config.mediaTypesRequiringUserActionForPlayback = .all
        let web = WKWebView(frame: CGRect(x: -2000, y: 0, width: 360, height: 640), configuration: config)
        web.customUserAgent = Self.agent
        web.alpha = 0.01
        web.isUserInteractionEnabled = false
        window.addSubview(web)
        defer {
            web.stopLoading()
            web.removeFromSuperview()
        }
        web.load(URLRequest(url: page))
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(500))
            let src = (try? await web.evaluateJavaScript(
                "(function(){var v=document.querySelector('video');return v?(v.currentSrc||v.src||((v.querySelector('source')||{}).src)||''):''})()")) as? String ?? ""
            var found = src.hasPrefix("http") ? URL(string: src) : nil
            if found == nil, let html = (try? await web.evaluateJavaScript("document.documentElement.outerHTML")) as? String {
                found = Self.scan(html)
            }
            if let found {
                let cookies = await config.websiteDataStore.httpCookieStore.allCookies()
                return Clip(url: found, cookies: cookies, referer: referer)
            }
        }
        return nil
    }

    /// The video file in the page's data: Instagram's `video_url`, TikTok's
    /// `playAddr`, JSON-escaped once or twice.
    static func scan(_ html: String) -> URL? {
        for pattern in [#"video_url\\*"\s*:\s*\\*"(https?:[^"]+?)\\*""#, #"playAddr\\*"\s*:\s*\\*"(https?:[^"]+?)\\*""#] {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let r = Range(m.range(at: 1), in: html) else { continue }
            let s = String(html[r])
                .replacingOccurrences(of: "\\u0026", with: "&")
                .replacingOccurrences(of: "\\u002F", with: "/")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "\\", with: "")
            if let url = URL(string: s) { return url }
        }
        return nil
    }
}

/// The clip's player: loops; a tap pauses or plays, like Instagram and
/// TikTok (owner, 2026-11-16: "play/pause, never open it as url"). The
/// first tap on a muted clip turns the sound on instead.
@MainActor @Observable final class ClipPlayback {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    var paused = false
    var muted: Bool

    init(clip: ClipResolver.Clip, muted: Bool) {
        let asset = AVURLAsset(url: clip.url, options: [
            AVURLAssetHTTPCookiesKey: clip.cookies,
            "AVURLAssetHTTPHeaderFieldsKey": ["Referer": clip.referer, "User-Agent": ClipResolver.agent],
        ])
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
        self.muted = muted
        player.isMuted = muted
        if !muted { Self.sound() }
        player.play()
    }

    /// Returns true when the tap turned the sound on.
    func tap() -> Bool {
        if muted {
            muted = false
            player.isMuted = false
            Self.sound()
            if paused { paused = false; player.play() }
            return true
        }
        paused.toggle()
        if paused { player.pause() } else { player.play() }
        return false
    }

    func stop() {
        player.pause()
        looper?.disableLooping()
    }

    private static func sound() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

/// The video layer, no controls.
private struct PlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {}
}

struct NativeClip: View {
    let clip: ClipResolver.Clip
    let muted: Bool
    var unmuted: () -> Void = {}
    @State private var playback: ClipPlayback?

    var body: some View {
        ZStack {
            Color.black
            if let playback {
                PlayerLayer(player: playback.player)
                if playback.paused {
                    Image(systemName: "play.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 8)
                        .allowsHitTesting(false)
                } else if playback.muted {
                    Image(systemName: "speaker.slash.fill")
                        .font(.caption.weight(.semibold))
                        .padding(8)
                        .background(.black.opacity(0.5), in: Circle())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if playback?.tap() == true { unmuted() }
        }
        .onAppear { if playback == nil { playback = ClipPlayback(clip: clip, muted: muted) } }
        .onDisappear {
            playback?.stop()
            playback = nil
        }
    }
}

/// Instagram or TikTok: the system player when the file is found, else the
/// embed. Started muted by autoplay and nothing found: `failed` (the card
/// shows its poster again; a tap then opens the embed).
struct ClipPlayer: View {
    let video: VerticalVideo
    let muted: Bool
    var failed: () -> Void = {}
    /// The sound went on by a tap: a "play" signal.
    var unmuted: () -> Void = {}
    @State private var clip: ClipResolver.Clip?
    @State private var looked = false

    var body: some View {
        ZStack {
            Color.black
            if let clip {
                NativeClip(clip: clip, muted: muted, unmuted: unmuted)
            } else if looked {
                if !muted { VerticalPlayer(video: video, muted: false) }
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: video) {
            guard !looked else { return }
            clip = await ClipResolver.shared.clip(for: video)
            looked = true
            if clip == nil, muted { failed() }
        }
    }
}
