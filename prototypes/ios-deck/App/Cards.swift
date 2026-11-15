import SwiftUI

/// One link as a card: theme strip, kind and length, title, where it is
/// from, then the text (transcript excerpt, passage, summary). Text first;
/// a video is a still image, never playing.
struct CardView: View {
    @Environment(Store.self) private var store
    let item: Item
    var compact = false

    var body: some View {
        let color = store.color(item.theme)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(item.theme).font(.caption.weight(.semibold)).foregroundStyle(color)
                Spacer()
                Image(systemName: item.symbol)
                if let length = item.length { Text(length) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let image = item.image, let url = URL(string: image), !compact {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(color.opacity(0.12))
                    }
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottomLeading) {
                    if item.isVideo {
                        Label(item.transcript.isEmpty ? "Video" : "Transcript below", systemImage: "captions.bubble")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(8)
                    }
                }
            }

            Text(item.title)
                .font(.title3.weight(.semibold))
                .lineLimit(compact ? 2 : 4)
            Text([item.author, item.site].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)

            if !item.summary.isEmpty {
                Text(item.summary).font(.callout).lineLimit(compact ? 3 : 5)
            }
            if !item.excerpt.isEmpty, !compact {
                Text(item.excerpt)
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(7)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) { Rectangle().fill(color.opacity(0.5)).frame(width: 3) }
            }
            Spacer(minLength: 0)
            HStack {
                Text("Tap to read").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}

/// The full saved text, then the original link. Opening the original is a
/// deliberate second step.
struct ReaderView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: Item

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.theme).font(.caption.weight(.semibold)).foregroundStyle(store.color(item.theme))
                    Text(item.title).font(.title2.weight(.bold))
                    Text([item.author, item.site, item.length].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    if !item.summary.isEmpty {
                        Text(item.summary).font(.callout).padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)))
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
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var paragraphs: [String] {
        let source = item.text.isEmpty ? item.passage : item.text
        return source.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
