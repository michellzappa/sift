import SwiftUI

/// The Scan / Watch / Read switch in the toolbar of every list (Today,
/// feeds, library). One setting, `AppModel.listMode`; keys 0 to 3.
/// Fixed labels, so the toolbar item keeps its size.
struct ModePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Picker("Mode", selection: Binding(get: { model.listMode?.rawValue ?? "" },
                                          set: { model.listMode = ReadingMode(rawValue: $0) })) {
            Text("All").tag("")
            ForEach(ReadingMode.allCases) { m in
                Label(m.title, systemImage: m.symbol).tag(m.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.titleAndIcon)
        .fixedSize()
        .help("Scan headlines, watch videos or read long texts (0, 1, 2, 3)")
    }
}

/// A video as a card for Watch: the picture at its own shape (tall for
/// Shorts, TikTok and reels), the length, the title and who made it.
struct WatchCard: View {
    let title: String
    let byline: String
    let image: String?
    let vertical: Bool
    let seconds: Int?
    let seen: Bool
    let selected: Bool
    var kept = false

    static let width: CGFloat = 220
    static let column = GridItem(.adaptive(minimum: width, maximum: width + 40), spacing: 16, alignment: .top)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Rectangle().fill(Color.secondary.opacity(0.12))
                    .overlay {
                        if let image, let url = URL(string: image) {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image { img.resizable().scaledToFill() }
                                else { Image(systemName: "play.rectangle").font(.title).foregroundStyle(.tertiary) }
                            }
                        } else {
                            Image(systemName: "play.rectangle").font(.title).foregroundStyle(.tertiary)
                        }
                    }
                    .clipped()
                if let seconds {
                    Text(TabCard.length(seconds)).font(.caption2.weight(.semibold)).monospacedDigit()
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .aspectRatio(vertical ? 9.0 / 16.0 : 16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .saturation(seen && !kept ? 0 : 1)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3))
            HStack(alignment: .top, spacing: 6) {
                Text(title).font(.callout.weight(seen && !kept ? .regular : .semibold))
                    .foregroundStyle(seen && !kept ? .secondary : .primary)
                    .lineLimit(2)
                Spacer(minLength: 6)
                if kept {
                    Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption).padding(.top, 2)
                } else if !seen {
                    Circle().fill(Color.accentColor).frame(width: 7, height: 7).padding(.top, 5)
                }
            }
            Text(byline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}
