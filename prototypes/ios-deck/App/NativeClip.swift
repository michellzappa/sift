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

/// The system player for a clip: loops, its own full-screen button
/// (turns with the phone), picture in picture.
struct NativeClip: UIViewControllerRepresentable {
    let clip: ClipResolver.Clip
    let muted: Bool

    final class Coordinator { var looper: AVPlayerLooper? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let asset = AVURLAsset(url: clip.url, options: [
            AVURLAssetHTTPCookiesKey: clip.cookies,
            "AVURLAssetHTTPHeaderFieldsKey": ["Referer": clip.referer, "User-Agent": ClipResolver.agent],
        ])
        let player = AVQueuePlayer()
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
        player.isMuted = muted
        if !muted {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.view.backgroundColor = .black
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.player?.pause()
        coordinator.looper?.disableLooping()
        controller.player = nil
    }
}

/// Instagram or TikTok: the system player when the file is found, else the
/// embed. Started muted by autoplay and nothing found: `failed` (the card
/// shows its poster again; a tap then opens the embed).
struct ClipPlayer: View {
    let video: VerticalVideo
    let muted: Bool
    var failed: () -> Void = {}
    @State private var clip: ClipResolver.Clip?
    @State private var looked = false

    var body: some View {
        ZStack {
            Color.black
            if let clip {
                NativeClip(clip: clip, muted: muted)
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
