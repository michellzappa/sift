import SwiftUI
import WebKit

/// The item's picture: the image from the Deck folder, else the web image
/// (a page's Open Graph image, a YouTube thumbnail), else a theme tint.
struct ItemImage: View {
    @Environment(Store.self) private var store
    let item: Item
    var height: CGFloat

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
            } else if let s = item.image, let url = URL(string: s) {
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

    var body: some View {
        let color = store.color(item.theme)
        let picture = item.imageFile != nil || item.image != nil
        VStack(alignment: .leading, spacing: 0) {
            if picture || item.video != nil {
                ItemImage(item: item, height: compact ? 120 : (tall ? 330 : 210))
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

                if !item.summary.isEmpty {
                    Text(item.summary).font(.callout).lineLimit(compact ? 3 : (picture ? 4 : 6))
                }
                if !compact {
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
                Spacer(minLength: 0)
                Text(item.video != nil ? "Tap to watch" : "Tap to open").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}

/// The full item: the video player or the picture, summary, key lines, then
/// all the saved text or the transcript. The original is a last, deliberate link.
struct ReaderView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: Item

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let video = item.video, video.provider == "youtube" {
                        YouTubePlayer(id: video.id)
                            .aspectRatio(16 / 9, contentMode: .fit)
                    } else if item.imageFile != nil || item.image != nil {
                        ItemImage(item: item, height: 260)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text(item.theme).font(.caption.weight(.semibold)).foregroundStyle(store.color(item.theme))
                        Text(item.title).font(.title2.weight(.bold))
                        Text([item.author, item.site, item.year, item.readTime].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
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
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                            Text(p).font(.body).lineSpacing(4)
                        }
                        if let url = URL(string: item.url) {
                            Link(destination: url) { Label("Open the original", systemImage: "safari") }
                                .padding(.top, 10)
                        }
                    }
                    .padding(20)
                    .textSelection(.enabled)
                }
            }
            .ignoresSafeArea(edges: .top)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var paragraphs: [String] {
        let source = !item.transcript.isEmpty ? item.text : (item.text.isEmpty ? item.passage : item.text)
        // Captions come as one block: break them every few sentences or 80 words.
        var out: [String] = []
        for block in source.components(separatedBy: "\n\n") {
            let b = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !b.isEmpty else { continue }
            let words = b.split(separator: " ")
            if words.count > 160 {
                stride(from: 0, to: words.count, by: 80).forEach { out.append(words[$0..<min($0 + 80, words.count)].joined(separator: " ")) }
            } else {
                out.append(b)
            }
        }
        return out
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
