import SwiftUI

/// The reader's look, in one place for the Mac and the phone (the phone's
/// project.yml compiles this file too): the column width, the text sizes,
/// line height and spacing, and the Markdown blocks drawn with them.
/// Owner, 2026-11-17: "a nicer reading mode … think Reeder, Instapaper,
/// Pocket … just the basics".
///
/// The reader settings are two keys in UserDefaults, shared by every reader
/// view on the device: `reader.size` (a step, 0 to 4) and `reader.serif`
/// (New York when true, the system sans when false; serif by default).
struct ReaderStyle: Equatable {
    static let sizeKey = "reader.size"
    static let serifKey = "reader.serif"
    static let defaultStep = 2

    /// Body sizes in points, five steps. The Mac's text is 13 pt elsewhere,
    /// the phone's 17 pt: the reader sits a few points above each.
    #if os(macOS)
    static let sizes: [CGFloat] = [14, 15, 17, 19, 22]
    static let margin: CGFloat = 32
    #else
    static let sizes: [CGFloat] = [15, 16, 18, 20, 23]
    static let margin: CGFloat = 24
    #endif

    let size: CGFloat
    let serif: Bool

    init(size: CGFloat, serif: Bool) {
        self.size = size
        self.serif = serif
    }

    init(step: Int, serif: Bool) {
        self.init(size: Self.sizes[min(max(step, 0), Self.sizes.count - 1)], serif: serif)
    }

    static let standard = ReaderStyle(step: defaultStep, serif: true)
    /// The phone's Today cards show the start of an article: small sans.
    static let card = ReaderStyle(size: 15, serif: false)

    var design: Font.Design { serif ? .serif : .default }
    var body: Font { .system(size: size, design: design) }
    /// SwiftUI's natural line height is about 1.2 times the size; this
    /// brings it to about 1.5.
    var lineSpacing: CGFloat { (size * 0.3).rounded() }
    /// Space between paragraphs: about one line.
    var paragraphSpacing: CGFloat { (size * 0.95).rounded() }
    /// About 68 characters a line: an average character is about half the size.
    var measure: CGFloat { size * 34 }
    var title: Font { .system(size: (size * 1.7).rounded(), weight: .bold, design: design) }
    var byline: Font { .system(size: (size * 0.76).rounded()) }
    var code: Font { .system(size: (size * 0.82).rounded(), design: .monospaced) }

    func heading(_ level: Int) -> Font {
        switch level {
        case ...1: .system(size: (size * 1.45).rounded(), weight: .bold, design: design)
        case 2: .system(size: (size * 1.25).rounded(), weight: .bold, design: design)
        case 3: .system(size: (size * 1.1).rounded(), weight: .semibold, design: design)
        default: .system(size: size, weight: .semibold, design: design)
        }
    }

    /// "6 min read" at 230 words a minute.
    static func readingTime(words: Int) -> String? {
        guard words > 0 else { return nil }
        return "\(max(1, Int((Double(words) / 230).rounded()))) min read"
    }

    static func words(_ text: String) -> Int {
        text.split { $0.isWhitespace }.count
    }
}

extension EnvironmentValues {
    @Entry var readerStyle: ReaderStyle = .standard
}

/// The reading column: the style from the settings, the measure centred in
/// the space there is, margins on both sides.
struct ReaderColumn: ViewModifier {
    @AppStorage(ReaderStyle.sizeKey) private var step = ReaderStyle.defaultStep
    @AppStorage(ReaderStyle.serifKey) private var serif = true

    func body(content: Content) -> some View {
        let style = ReaderStyle(step: step, serif: serif)
        content
            .environment(\.readerStyle, style)
            .textSelection(.enabled)
            .frame(maxWidth: style.measure, alignment: .leading)
            .padding(.horizontal, ReaderStyle.margin)
            .padding(.vertical, ReaderStyle.margin)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func readerColumn() -> some View { modifier(ReaderColumn()) }
}

/// A large title, then a quiet line: site, author, date, reading time.
struct ReaderHeader: View {
    @Environment(\.readerStyle) private var style
    let title: String
    let byline: [String?]

    var body: some View {
        VStack(alignment: .leading, spacing: style.size * 0.5) {
            Text(title).font(style.title)
                .fixedSize(horizontal: false, vertical: true)
            let line = byline.compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
            if !line.isEmpty {
                Text(line).font(style.byline).foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, style.size * 0.4)
    }
}

/// A whole Markdown text, block by block, with paragraph spacing.
struct ReaderText: View {
    @Environment(\.readerStyle) private var style
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: style.paragraphSpacing) {
            ForEach(Array(Self.blocks(markdown).enumerated()), id: \.offset) { _, block in
                ReaderBlock(block: block)
            }
        }
    }

    /// Blocks split on blank lines, keeping ``` code blocks whole. A long
    /// block of captions breaks every 80 words.
    static func blocks(_ text: String) -> [String] {
        var out: [String] = []
        var code: String?
        for part in text.components(separatedBy: "\n\n") {
            if var c = code {
                c += "\n\n" + part
                if part.hasSuffix("```") { out.append(c); code = nil } else { code = c }
            } else if part.hasPrefix("```"), !(part.count > 3 && part.hasSuffix("```")) {
                code = part
            } else {
                out.append(part)
            }
        }
        if let c = code { out.append(c) }
        out = out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        // Text saved before 1.4.2 can have a lone ">" before the quoted
        // paragraph: it quotes the next block.
        var merged: [String] = []
        var quoteNext = false
        for block in out {
            if block == ">" { quoteNext = true; continue }
            let b = quoteNext && !block.hasPrefix(">") ? "> " + block : block
            quoteNext = false
            let words = b.split(separator: " ")
            if words.count > 160, !b.hasPrefix("```"), !b.contains("\n") {
                stride(from: 0, to: words.count, by: 80).forEach { merged.append(words[$0..<min($0 + 80, words.count)].joined(separator: " ")) }
            } else {
                merged.append(b)
            }
        }
        return merged
    }
}

/// One Markdown block: a heading, a quote, a list, a code block, an image,
/// a rule or a paragraph. Inline Markdown (links, emphasis, code) renders
/// natively; links take the tint and open through the view's `openURL`.
struct ReaderBlock: View {
    @Environment(\.readerStyle) private var style
    let block: String

    var body: some View {
        let b = block.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.hasPrefix("```") {
            Text(b.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .newlines))
                .font(style.code)
                .lineSpacing(style.lineSpacing * 0.5)
                .padding(style.size * 0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
        } else if let level = Self.headingLevel(b) {
            Text(Self.inline(String(b.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
                .font(style.heading(level))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, style.size * 0.4)
        } else if b.hasPrefix(">") {
            Text(Self.inline(b.split(separator: "\n").map { $0.drop { $0 == ">" || $0 == " " } }.joined(separator: "\n")))
                .font(style.body)
                .lineSpacing(style.lineSpacing)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, style.size)
                .overlay(alignment: .leading) { Capsule().fill(Color.secondary.opacity(0.45)).frame(width: 2) }
        } else if let url = Self.image(b) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if phase.error == nil {
                    RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)).frame(height: 160)
                }
            }
        } else if b == "---" || b == "***" {
            Divider().padding(.vertical, style.size * 0.5)
        } else if Self.listMarker(b) != nil {
            VStack(alignment: .leading, spacing: style.size * 0.4) {
                ForEach(Array(b.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                    let item = String(line).trimmingCharacters(in: .whitespaces)
                    let marker = Self.listMarker(item)
                    HStack(alignment: .firstTextBaseline, spacing: style.size * 0.5) {
                        Text(marker.map { $0.number ?? "•" } ?? "")
                            .foregroundStyle(.secondary)
                            .frame(width: style.size * 1.1, alignment: .trailing)
                        Text(Self.inline(marker.map { String(item.dropFirst($0.length)) } ?? item))
                            .lineSpacing(style.lineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(style.body)
            .padding(.leading, style.size * 0.3)
        } else {
            Text(Self.inline(b))
                .font(style.body)
                .lineSpacing(style.lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func headingLevel(_ s: String) -> Int? {
        let hashes = s.prefix { $0 == "#" }.count
        return (1...6).contains(hashes) && s.dropFirst(hashes).hasPrefix(" ") ? hashes : nil
    }

    /// "- ", "* " or "1. " at the start of a line: the marker's length and,
    /// for a numbered list, the number to show.
    static func listMarker(_ s: String) -> (length: Int, number: String?)? {
        if s.hasPrefix("- ") || s.hasPrefix("* ") { return (2, nil) }
        let digits = s.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 3, s.dropFirst(digits.count).hasPrefix(". ") {
            return (digits.count + 2, String(digits) + ".")
        }
        return nil
    }

    /// A block that is one image, `![alt](address)`.
    static func image(_ s: String) -> URL? {
        guard s.hasPrefix("!["), s.hasSuffix(")"), !s.contains("\n"),
              let open = s.range(of: "](") else { return nil }
        let inside = s[open.upperBound..<s.index(before: s.endIndex)]
        let address = inside.split(separator: " ").first.map(String.init) ?? ""
        guard address.hasPrefix("http") else { return nil }
        return URL(string: address)
    }

    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

/// Text size (five steps) and serif or sans, for every reader on the device.
struct ReaderSettings: View {
    @AppStorage(ReaderStyle.sizeKey) private var step = ReaderStyle.defaultStep
    @AppStorage(ReaderStyle.serifKey) private var serif = true

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button { step = max(step - 1, 0) } label: {
                    Image(systemName: "textformat.size.smaller").frame(width: 28, height: 24)
                }
                .disabled(step <= 0)
                .help("Smaller text")
                HStack(spacing: 6) {
                    ForEach(0..<ReaderStyle.sizes.count, id: \.self) { i in
                        Circle().fill(i <= step ? Color.primary : Color.secondary.opacity(0.3)).frame(width: 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
                Button { step = min(step + 1, ReaderStyle.sizes.count - 1) } label: {
                    Image(systemName: "textformat.size.larger").frame(width: 28, height: 24)
                }
                .disabled(step >= ReaderStyle.sizes.count - 1)
                .help("Larger text")
            }
            Picker("Font", selection: $serif) {
                Text("Serif").tag(true)
                Text("Sans").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .buttonStyle(.borderless)
        .padding(16)
        .frame(width: 230)
    }
}

/// The "Aa" button that opens the reader settings.
struct ReaderSettingsButton: View {
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: { Image(systemName: "textformat.size") }
            .help("Text size and font")
            .accessibilityLabel("Text size and font")
            .popover(isPresented: $showing) {
                ReaderSettings().presentationCompactAdaptation(.popover)
            }
    }
}

#if os(macOS)
/// View > Larger Text (Command-plus) and Smaller Text (Command-minus).
struct ReaderTextCommands: View {
    @AppStorage(ReaderStyle.sizeKey) private var step = ReaderStyle.defaultStep

    var body: some View {
        Button("Larger Text") { step = min(step + 1, ReaderStyle.sizes.count - 1) }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(step >= ReaderStyle.sizes.count - 1)
        Button("Smaller Text") { step = max(step - 1, 0) }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(step <= 0)
    }
}
#endif
