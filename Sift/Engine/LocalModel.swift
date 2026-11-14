import Foundation
import IOKit.ps
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model (Foundation Models framework, Apple Intelligence,
/// macOS 26 and later). Free, private and offline. Sift uses it where a small
/// model fits, with Claude as the fallback:
/// - first pass per new link: errand, noise or keep (`firstPass`)
/// - one pick from the current themes per new link (`pickTheme`)
/// - one short paragraph per captured page or transcript (`summarize`)
///
/// The model's context window is 4,096 tokens (instructions, prompt, schema
/// and answer together) on macOS 26. The macOS 26 SDK has no API that reports
/// it, so `chunkCharacters` is a fixed, conservative size. Every call uses a
/// fresh session, so no transcript grows across links.
///
/// The app still runs on macOS 14: everything here is behind
/// `#available(macOS 26, *)` and `SystemLanguageModel.default.availability`,
/// and the framework is weak-linked (project.yml).
enum LocalModel {
    enum Status: Sendable, Equatable {
        case available
        case appleIntelligenceOff
        case notSupported
        case notReady
        case needsNewerMacOS

        /// Plain words for Settings.
        var label: String {
            switch self {
            case .available: "Available"
            case .appleIntelligenceOff: "Apple Intelligence is off"
            case .notSupported: "Not supported on this Mac"
            case .notReady: "The model is still downloading"
            case .needsNewerMacOS: "Needs macOS 26 or later"
            }
        }
    }

    static var status: Status {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(.appleIntelligenceNotEnabled): return .appleIntelligenceOff
            case .unavailable(.modelNotReady): return .notReady
            case .unavailable: return .notSupported
            }
        }
        #endif
        return .needsNewerMacOS
    }

    static var isAvailable: Bool { status == .available }

    /// True when the Mac runs on its battery. Summaries wait for power.
    static var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
        else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }

    // MARK: First pass

    enum Kind: String, Sendable { case errand, noise, keep }

    struct Verdict: Sendable {
        let kind: Kind
        /// Only a sure answer skips Claude.
        let sure: Bool
    }

    /// Errand, noise or keep for one link. Nil when the model cannot answer
    /// (unavailable, guardrail, language, context); the link then goes to Claude.
    static func firstPass(title: String, url: String, preview: String) async -> Verdict? {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *), isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            You sort one saved web link at a time. Answer with a kind and a confidence.
            errand: a page open for a task, not out of curiosity: an order, account, login, cart, \
            checkout, booking, search results page, map, mail, dashboard, or a document being edited.
            noise: a page with no lasting value: a home page, engagement bait, a viral claim, an empty \
            or broken page.
            keep: anything that could feed an interest, a project or reading: articles, papers, videos, \
            tools, posts with ideas. When in doubt, answer keep.
            Confidence is high only when the title and URL leave no doubt.
            """)
        do {
            let answer = try await session.respond(
                to: linkPrompt(title: title, url: url, preview: preview),
                generating: FirstPassAnswer.self,
                options: GenerationOptions(sampling: .greedy)
            ).content
            let kind: Kind = switch answer.kind {
            case .errand: .errand
            case .noise: .noise
            case .keep: .keep
            }
            return Verdict(kind: kind, sure: answer.confidence == .high)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: Sorting into themes

    struct ThemeHint: Sendable {
        let name, summary, notes: String
    }

    struct Pick: Sendable {
        let theme: String
        let sure: Bool
    }

    /// One of the current themes for one link. Nil when the model has no
    /// pick, picks "none", or cannot answer; the link then goes to Claude.
    static func pickTheme(title: String, url: String, preview: String, themes: [ThemeHint]) async -> Pick? {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *), isAvailable, !themes.isEmpty else { return nil }
        let names = themes.map(\.name)
        let catalogue = themes.map { t in
            var line = "- \(t.name): \(t.summary.prefix(160))"
            if !t.notes.isEmpty { line += " Owner's note: \(t.notes.prefix(140))" }
            return line.replacingOccurrences(of: "\n", with: " ")
        }.joined(separator: "\n")
        let instructions = """
            You put one saved web link into one of a person's themes. A theme is a sustained interest. \
            Choose the theme the link could feed. Answer "none" when no theme fits well. Confidence is \
            high only when the link clearly belongs to that theme and to no other.

            Themes:
            \(catalogue)
            """
        do {
            let root = DynamicGenerationSchema(name: "ThemeChoice", properties: [
                .init(name: "theme", description: "One theme name from the list, or none",
                      schema: DynamicGenerationSchema(name: "ThemeName", anyOf: names + ["none"])),
                .init(name: "confidence", description: "How sure the choice is",
                      schema: DynamicGenerationSchema(name: "Confidence", anyOf: ["high", "medium", "low"])),
            ])
            let schema = try GenerationSchema(root: root, dependencies: [])
            let session = LanguageModelSession(instructions: instructions)
            let content = try await session.respond(
                to: linkPrompt(title: title, url: url, preview: preview),
                schema: schema,
                options: GenerationOptions(sampling: .greedy)
            ).content
            let theme = try content.value(String.self, forProperty: "theme")
            let confidence = try content.value(String.self, forProperty: "confidence")
            guard names.contains(theme) else { return nil }
            return Pick(theme: theme, sure: confidence == "high")
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: Summaries

    enum SummaryOutcome: Sendable {
        case summary(String)
        /// The model will not summarize this text (guardrail, language, no text).
        case skip
        /// Try again later (model busy, rate limited, not available now).
        case later
    }

    /// About 2,000 tokens of text per chunk, at a conservative 3 characters
    /// per token, so a chunk, its instructions and the answer fit in 4,096.
    static let chunkCharacters = 6_000
    /// Long texts and transcripts: only the first chunks are read.
    static let maxChunks = 6

    /// One short paragraph for a captured page or transcript. Long texts are
    /// summarized chunk by chunk, then the chunk notes become one paragraph.
    static func summarize(title: String, text: String) async -> SummaryOutcome {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *), isAvailable else { return .later }
        let chunks = chunked(text)
        guard !chunks.isEmpty else { return .skip }
        do {
            if chunks.count == 1 {
                return .summary(try await summarizeChunk(title: title, text: chunks[0], final: true))
            }
            var notes: [String] = []
            for chunk in chunks {
                notes.append(try await summarizeChunk(title: title, text: chunk, final: false))
            }
            return .summary(try await combine(title: title, notes: notes))
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .rateLimited, .concurrentRequests, .assetsUnavailable: return .later
            default: return .skip
            }
        } catch {
            return .skip
        }
        #else
        return .later
        #endif
    }

    /// Splits text at paragraph breaks into chunks of at most `chunkCharacters`.
    static func chunked(_ text: String) -> [String] {
        let paragraphs = text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var chunks: [String] = []
        var current = ""
        for p in paragraphs {
            // A paragraph longer than a chunk is cut into pieces.
            var rest = Substring(p)
            while !rest.isEmpty {
                let room = chunkCharacters - current.count
                if room < 200, !current.isEmpty {
                    chunks.append(current); current = ""
                    if chunks.count == maxChunks { return chunks }
                    continue
                }
                let piece = rest.prefix(room)
                current += (current.isEmpty ? "" : "\n\n") + piece
                rest = rest.dropFirst(piece.count)
            }
        }
        if !current.isEmpty, chunks.count < maxChunks { chunks.append(current) }
        return chunks
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private static func linkPrompt(title: String, url: String, preview: String) -> String {
        var p = "Title: \(title.isEmpty ? "(no title)" : String(title.prefix(200)))\nURL: \(url.prefix(300))"
        if !preview.isEmpty { p += "\nPreview: \(preview.prefix(400))" }
        return p
    }

    @available(macOS 26, *)
    private static var summaryModel: SystemLanguageModel {
        SystemLanguageModel(guardrails: .permissiveContentTransformations)
    }

    @available(macOS 26, *)
    private static func summarizeChunk(title: String, text: String, final: Bool) async throws -> String {
        let instructions = final
            ? "You summarize a saved web page or video transcript in one short paragraph of two to four sentences: what it is and its main points. Write in the language of the text. Plain prose, no lists, no headings, no preamble."
            : "You summarize one part of a longer saved web page or video transcript in two sentences: its main points. Write in the language of the text. Plain prose, no preamble."
        let tokens = final ? 220 : 120
        do {
            let session = LanguageModelSession(model: summaryModel, instructions: instructions)
            return try await respondText(session, "Title: \(title)\n\n\(text)", tokens: tokens)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // Denser text than expected (more tokens per character): try once
            // with the first half, in a fresh session.
            let session = LanguageModelSession(model: summaryModel, instructions: instructions)
            return try await respondText(session, "Title: \(title)\n\n\(text.prefix(text.count / 2))", tokens: tokens)
        }
    }

    @available(macOS 26, *)
    private static func combine(title: String, notes: [String]) async throws -> String {
        let session = LanguageModelSession(model: summaryModel, instructions: "You get notes on the parts of one saved web page or video transcript, in order. Write one short paragraph of two to four sentences that summarizes the whole: what it is and its main points. Write in the language of the notes. Plain prose, no lists, no preamble.")
        let joined = notes.enumerated().map { "Part \($0.offset + 1): \($0.element)" }.joined(separator: "\n")
        return try await respondText(session, "Title: \(title)\n\n\(joined)", tokens: 220)
    }

    @available(macOS 26, *)
    private static func respondText(_ session: LanguageModelSession, _ prompt: String, tokens: Int) async throws -> String {
        let text = try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy, maximumResponseTokens: tokens)).content
        return text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
    #endif
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
private enum LinkKindChoice {
    case errand, noise, keep
}

@available(macOS 26, *)
@Generable
private enum ConfidenceChoice {
    case high, medium, low
}

@available(macOS 26, *)
@Generable
private struct FirstPassAnswer {
    @Guide(description: "errand, noise or keep")
    var kind: LinkKindChoice
    @Guide(description: "How sure the answer is")
    var confidence: ConfidenceChoice
}
#endif
