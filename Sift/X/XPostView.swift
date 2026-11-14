import AVKit
import SwiftUI

/// An X post drawn natively, no web view. Follows X's display requirements
/// for posts shown outside the embed: avatar, name and @handle linked to the
/// profile, unmodified text, links shown as display_url but pointing at the
/// t.co URL, timestamp linked to the post, the X mark top right, "View on
/// X", and an edit label.
struct XPostView: View {
    let post: XPost
    var quoted: XPost?
    var nested = false
    @State private var playing: String?

    var body: some View {
        if post.removed {
            Label("This post is no longer available on X.", systemImage: "eye.slash")
                .font(.callout).foregroundStyle(.secondary)
                .padding(14)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                header
                if let reply = post.replyTo, !nested {
                    (Text("Replying to ") + Text("@\(reply)").foregroundColor(.accentColor)).font(.caption).foregroundStyle(.secondary)
                }
                Text(Self.attributed(post)).font(nested ? .callout : .body).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !post.media.isEmpty { mediaGrid }
                ForEach(post.links.filter { !$0.isMedia && $0.title != nil }, id: \.tco) { linkCard($0) }
                if let quoted, !nested {
                    XPostView(post: quoted, nested: true)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
                }
                footer
            }
            .padding(nested ? 12 : 16)
        }
    }

    private var profile: URL? { post.author.flatMap { URL(string: "https://x.com/\($0.username)") } }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Link(destination: profile ?? URL(string: "https://x.com")!) {
                AsyncImage(url: post.author?.avatar.flatMap(URL.init(string:))) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Circle().fill(.quaternary) }
                    .frame(width: nested ? 24 : 40, height: nested ? 24 : 40)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            Link(destination: profile ?? URL(string: "https://x.com")!) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(post.author?.name ?? "").font((nested ? Font.callout : .body).weight(.semibold)).foregroundStyle(.primary)
                    Text("@\(post.author?.username ?? "")").font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Text("𝕏").font(.title3.weight(.bold)).foregroundStyle(.primary)
                .accessibilityLabel("X")
        }
    }

    @ViewBuilder
    private var mediaGrid: some View {
        let columns = post.media.count == 1 ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(post.media.enumerated()), id: \.offset) { _, m in mediaTile(m) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func mediaTile(_ m: XPost.Media) -> some View {
        let ratio = CGFloat(m.width ?? 16) / CGFloat(max(m.height ?? 9, 1))
        if let video = m.video, playing == video, let url = URL(string: video) {
            VideoPlayer(player: AVPlayer(url: url))
                .aspectRatio(ratio, contentMode: .fit)
        } else {
            AsyncImage(url: URL(string: m.url ?? m.preview ?? "")) { image in
                image.resizable().aspectRatio(contentMode: post.media.count == 1 ? .fit : .fill)
            } placeholder: {
                Rectangle().fill(.quaternary).aspectRatio(ratio, contentMode: .fit)
            }
            .frame(maxHeight: post.media.count == 1 ? 520 : 200)
            .clipped()
            .overlay {
                if m.video != nil {
                    Image(systemName: "play.circle.fill").font(.system(size: 44)).foregroundStyle(.white).shadow(radius: 4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if let v = m.video { playing = v } }
            .help(m.alt ?? "")
            .accessibilityLabel(m.alt ?? (m.video != nil ? "Video" : "Image"))
        }
    }

    private func linkCard(_ link: XPost.Link) -> some View {
        Link(destination: URL(string: link.tco)!) {
            VStack(alignment: .leading, spacing: 3) {
                Text(link.title ?? link.display).font(.callout.weight(.semibold)).lineLimit(2)
                if let summary = link.summary, !summary.isEmpty {
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                Text(URL(string: link.expanded)?.host() ?? link.display).font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let created = post.created {
                Link(destination: URL(string: post.permalink)!) {
                    Text(created, format: .dateTime.hour().minute().day().month(.abbreviated).year())
                }
            }
            if post.edited { Text("· Edited") }
            Text("·")
            Link("View on X", destination: URL(string: post.permalink)!)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// The post text with links, mentions and hashtags linked. Entity offsets
    /// count Unicode code points. Links show their display URL and point at
    /// the t.co URL; links to the post's own media are removed.
    static func attributed(_ post: XPost) -> AttributedString {
        let scalars = Array(post.text.unicodeScalars)
        enum Kind { case link(XPost.Link), mention(String), tag(String) }
        var spans: [(start: Int, end: Int, kind: Kind)] = []
        spans += post.links.map { ($0.start, $0.end, .link($0)) }
        spans += post.mentions.map { ($0.start, $0.end, .mention($0.username)) }
        spans += post.tags.map { ($0.start, $0.end, .tag($0.tag)) }
        spans.sort { $0.start < $1.start }

        var out = AttributedString()
        var cursor = 0
        func plain(_ from: Int, _ to: Int) {
            guard from < to, from >= 0, to <= scalars.count else { return }
            var s = String.UnicodeScalarView(); s.append(contentsOf: scalars[from..<to])
            out += AttributedString(Self.unescape(String(s)))
        }
        for span in spans where span.start >= cursor && span.end <= scalars.count && span.start < span.end {
            plain(cursor, span.start)
            switch span.kind {
            case .link(let l):
                if !l.isMedia {
                    var a = AttributedString(l.display)
                    a.link = URL(string: l.tco)
                    out += a
                }
            case .mention(let name):
                var a = AttributedString("@\(name)")
                a.link = URL(string: "https://x.com/\(name)")
                out += a
            case .tag(let tag):
                var a = AttributedString("#\(tag)")
                a.link = URL(string: "https://x.com/hashtag/\(tag)")
                out += a
            }
            cursor = span.end
        }
        plain(cursor, scalars.count)
        return out
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }
}
