import SwiftUI
import WebKit

/// The item's picture: the image from the Deck folder, else the web image
/// (a page's Open Graph image, a YouTube thumbnail), else a theme tint.
struct ItemImage: View {
    @Environment(Store.self) private var store
    let item: Item
    var height: CGFloat
    /// An image found on the phone (Open Graph), when the deck had none.
    var fallback: String? = nil

    var body: some View {
        let tint = store.color(item.theme)
        // The box sets the size; the picture fills it as an overlay, so a
        // wide image can never push the card wider than the screen.
        Rectangle().fill(tint.opacity(0.14))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay { picture(tint) }
            .clipped()
    }

    @ViewBuilder private func picture(_ tint: Color) -> some View {
        if let local = store.localImage(item), let image = UIImage(contentsOfFile: local.path(percentEncoded: false)) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let s = item.image ?? fallback, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() }
                }
            } else {
                Image(systemName: item.symbol).font(.system(size: 34)).foregroundStyle(tint.opacity(0.6))
            }
    }

    var hasPicture: Bool { item.imageFile != nil || item.image != nil }
}

/// One link as a card: picture on top, then theme, title, who and how long,
/// the summary and the key lines. Text first; a video never plays here.
struct CardView: View {
    @Environment(Store.self) private var store
    let item: Item
    var compact = false
    /// Full-height page in the vertical deck: a taller picture.
    var tall = false
    /// Today cards: open with the article's own first paragraphs (from the
    /// full text), filling the card, instead of the short summary.
    var lede = false
    @State private var og: OpenGraph.Preview?

    /// Long enough to be worth a lede: more text than the summary shows.
    private var showLede: Bool { lede && item.text.count > max(item.summary.count + 80, 300) }

    /// The first blocks of the text, skipping a first paragraph that only
    /// repeats the title.
    private var ledeBlocks: [String] {
        let blocks = item.text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("```") && $0 != item.title }
        return Array(blocks.prefix(8))
    }

    var body: some View {
        if item.isXPost {
            // An X post reads as a post in the deck too (owner, 2026-11-17).
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(store.color(item.theme)).frame(width: 8, height: 8)
                    Text(item.theme).font(.caption.weight(.semibold)).foregroundStyle(store.color(item.theme)).lineLimit(1)
                }
                XPostCard(post: item.xPost)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            articleCard
        }
    }

    @ViewBuilder private var articleCard: some View {
        let color = store.color(item.theme)
        let picture = item.imageFile != nil || item.image != nil || og?.image != nil
        let summary = item.summary.isEmpty ? (og?.description ?? "") : item.summary
        VStack(alignment: .leading, spacing: 0) {
            if picture || item.video != nil {
                ItemImage(item: item, height: compact ? 120 : (showLede ? 200 : (tall ? 330 : 210)), fallback: og?.image)
                    .overlay {
                        if item.video != nil {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white, .black.opacity(0.35))
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if !item.transcript.isEmpty {
                            Label("Transcript", systemImage: "captions.bubble")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(10)
                        }
                    }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(item.theme).font(.caption.weight(.semibold)).foregroundStyle(color).lineLimit(1)
                    Spacer()
                    Image(systemName: item.symbol)
                    if let t = item.readTime { Text(t) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(item.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(compact ? 2 : 3)
                Text([item.author, item.site, item.year].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)

                if showLede {
                    // The article's opening, as far as the card goes, fading out.
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(ledeBlocks.enumerated()), id: \.offset) { _, block in
                            ReaderBlock(block: block)
                        }
                    }
                    .environment(\.readerStyle, .card)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.8),
                                                 .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                } else if !summary.isEmpty {
                    Text(summary).font(.callout).lineLimit(compact ? 3 : (picture ? 4 : 6))
                }
                if !compact, !showLede {
                    let lines = item.keyLines ?? []
                    if !lines.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(lines.prefix(picture ? 2 : 3).enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .padding(.leading, 10)
                                    .overlay(alignment: .leading) { Rectangle().fill(color.opacity(0.5)).frame(width: 2) }
                            }
                        }
                    } else if !item.excerpt.isEmpty {
                        Text(item.excerpt)
                            .font(.footnote).italic().foregroundStyle(.secondary)
                            .lineLimit(picture ? 4 : 8)
                    }
                }
                if !showLede { Spacer(minLength: 0) }
                Text(item.video != nil ? "Tap to watch" : (showLede ? "Tap to read on" : "Tap to open")).font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(color.opacity(0.35), lineWidth: 1))
        // No picture from the Mac: look for the page's own preview image.
        .task(id: item.id) {
            guard item.imageFile == nil, item.image == nil, item.video == nil else { return }
            og = await OpenGraph.shared.preview(for: item.url)
        }
    }
}

/// The full item: the video player or the picture, summary, key lines, then
/// all the saved text or the transcript. The original is a last, deliberate link.
struct ReaderView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let item: Item
    @State private var browsing: BrowserLink?
    @State private var trailFrom: Item?
    /// The content's frame in the scroll view and the visible height: the progress bar.
    @State private var content: CGRect = .zero
    @State private var viewport: CGFloat = 0
    private static let space = "reader"

    /// "Open in Instagram", TikTok, X or YouTube: the system hands the link
    /// to that app (its universal link), else to the website. Sift holds no
    /// login for these networks (ADR 0001, decision 5).
    @ViewBuilder private var openInApp: some View {
        if let app = Networks.appName(for: item.url), let url = URL(string: item.url) {
            Button { openURL(url) } label: { Label("Open in \(app)", systemImage: "arrow.up.forward.app") }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if item.isXPost {
                    // An X post reads as a post: who, when, the text, its pictures.
                    VStack(alignment: .leading, spacing: 14) {
                        Text(item.theme).font(.caption.weight(.semibold)).foregroundStyle(store.color(item.theme))
                        XPostCard(post: item.xPost)
                        openInApp.padding(.top, 6)
                        Button { trailFrom = item } label: { Label("More like this", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                    }
                    .padding(20)
                    .padding(.top, 40)
                    .textSelection(.enabled)
                } else {
                VStack(alignment: .leading, spacing: 0) {
                    if let video = item.video, video.provider == "youtube" {
                        YouTubePlayer(id: video.id)
                            .aspectRatio(16 / 9, contentMode: .fit)
                    } else if item.imageFile != nil || item.image != nil {
                        ItemImage(item: item, height: 260)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text(item.theme).font(.caption.weight(.semibold)).foregroundStyle(store.color(item.theme))
                        ReaderHeader(title: item.title, byline: [item.author, item.site, item.year, item.readTime])
                        if !item.summary.isEmpty {
                            Text(item.summary).font(.callout).padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)))
                        }
                        if let lines = item.keyLines, !lines.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Key lines").font(.headline)
                                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.callout).italic()
                                        .padding(.leading, 10)
                                        .overlay(alignment: .leading) { Rectangle().fill(store.color(item.theme).opacity(0.5)).frame(width: 3) }
                                }
                            }
                        }
                        if !item.transcript.isEmpty {
                            Text("Transcript").font(.headline).padding(.top, 6)
                        }
                        ReaderText(markdown: source)
                        openInApp.padding(.top, 10)
                        if let url = URL(string: item.url) {
                            // Safari inside the app, never the Safari app: a page
                            // opened there becomes a tab and comes back to Sift.
                            Button { browsing = BrowserLink(url: url) } label: { Label("Open the original", systemImage: "safari") }
                                .padding(.top, 10)
                        }
                        // A trail: more like this, from your saves and Today (Trail.swift).
                        Button { trailFrom = item } label: { Label("More like this", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                    }
                    .readerColumn()
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { content = $0 }
                }
            }
            .coordinateSpace(.named(Self.space))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
            .ignoresSafeArea(edges: .top)
            // A thin bar: how far through the text you are.
            .overlay(alignment: .top) {
                if !item.isXPost {
                    GeometryReader { g in
                        Rectangle().fill(Color.accentColor).frame(width: g.size.width * progress, height: 2)
                    }
                    .frame(height: 2)
                    .allowsHitTesting(false)
                }
            }
            .toolbar {
                if !item.isXPost { ToolbarItem(placement: .topBarLeading) { ReaderSettingsButton() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            // Links in the text open inside the app too.
            .environment(\.openURL, OpenURLAction { url in browsing = BrowserLink(url: url); return .handled })
            .sheet(item: $browsing) { InAppBrowser(url: $0.url).ignoresSafeArea() }
            .background { Color.clear.sheet(item: $trailFrom) { TrailSheet(seed: $0) } }
        }
    }

    /// The saved text or the transcript; else the passage the deck had.
    private var source: String {
        !item.transcript.isEmpty ? item.text : (item.text.isEmpty ? item.passage : item.text)
    }

    /// 0 at the top, 1 when the end of the text is on screen.
    private var progress: CGFloat {
        let room = content.height - viewport
        guard room > 1 else { return 0 }
        return min(max(-content.minY / room, 0), 1)
    }
}

/// An X post: avatar (when the Mac had one), name and @handle, date, the
/// text with its links, then the pictures. Links go through the reader's
/// `openURL`, so they open in the in-app browser.
struct XPostCard: View {
    let post: Item.XPostInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                AsyncImage(url: post.avatar.flatMap(URL.init(string:))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Circle().fill(Color(.tertiarySystemFill))
                            .overlay(Text(String((post.name ?? post.handle ?? "X").prefix(1))).font(.headline).foregroundStyle(.secondary))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.name ?? post.handle ?? "X").font(.body.weight(.semibold)).lineLimit(1)
                    if let handle = post.handle { Text("@\(handle)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                Text("𝕏").font(.title3.weight(.bold)).accessibilityLabel("X")
            }
            Text(Self.linked(post.text)).font(.body).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(post.images ?? [], id: \.self) { s in
                AsyncImage(url: URL(string: s)) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() } else { Color(.tertiarySystemFill).frame(height: 180) }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            if let date = post.date.flatMap(Self.parse) {
                Text(date, format: .dateTime.hour().minute().day().month(.abbreviated).year())
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(.separator).opacity(0.5)))
    }

    /// Markdown links stay links; bare addresses ("example.com/page") become links.
    static func linked(_ text: String) -> AttributedString {
        var out = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        let plain = String(out.characters)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return out }
        for m in detector.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
            guard let r = Range(m.range, in: plain), let url = m.url else { continue }
            let lo = out.characters.index(out.startIndex, offsetBy: plain.distance(from: plain.startIndex, to: r.lowerBound))
            let hi = out.characters.index(lo, offsetBy: plain.distance(from: r.lowerBound, to: r.upperBound))
            guard out[lo..<hi].link == nil else { continue }
            out[lo..<hi].link = url
        }
        return out
    }

    private static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withFullDate]
        return f.date(from: String(s.prefix(10)))
    }
}

/// YouTube's privacy-enhanced embed, inline, never autoplaying. The view
/// unloads the page when it goes away, so the sound stops at once.
struct YouTubePlayer: UIViewRepresentable {
    let id: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        let web = WKWebView(frame: .zero, configuration: config)
        web.scrollView.isScrollEnabled = false
        web.isOpaque = false
        web.backgroundColor = .black
        let html = """
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;background:#000}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style></head>
        <body><iframe src="https://www.youtube-nocookie.com/embed/\(id)?playsinline=1&rel=0&modestbranding=1" allow="encrypted-media; picture-in-picture" allowfullscreen></iframe></body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
        return web
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: ()) {
        view.pauseAllMediaPlayback()
        view.loadHTMLString("", baseURL: nil)
    }
}

/// A link to show in Safari inside the app.
struct BrowserLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

