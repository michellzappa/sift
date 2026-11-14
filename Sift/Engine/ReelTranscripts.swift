import AVFoundation
import Foundation
import NaturalLanguage
import Speech

/// What Instagram reels say, as text. The open-source `yt-dlp` tool
/// (Unlicense) fetches the reel's audio track without a login; macOS speech
/// recognition turns it into text; the audio file is deleted afterwards.
/// Like the YouTube tool, it is optional and lives in Sift's tools folder.
enum ReelTool {
    static var executable: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            TranscriptTool.installFolder.appending(path: "venv/bin/yt-dlp"),
            home.appending(path: ".local/bin/yt-dlp"),
            URL(filePath: "/opt/homebrew/bin/yt-dlp"),
            URL(filePath: "/usr/local/bin/yt-dlp"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
    }

    /// The gate key for reel downloads, apart from the image embeds.
    static let gate = "reels.instagram.com"

    static func isReel(_ url: String) -> Bool {
        guard let u = URL(string: url), u.host()?.lowercased().hasSuffix("instagram.com") == true else { return false }
        let first = u.pathComponents.dropFirst().first ?? ""
        return first == "reel" || first == "reels" || first == "tv"
    }

    enum Outcome: Sendable { case audio(URL), none, throttled }

    /// Downloads the audio track of one reel into a temporary folder.
    static func audio(for url: String) async -> Outcome {
        guard let exe = executable else { return .none }
        guard await HostGate.shared.admit(gate) else { return .throttled }
        let dir = FileManager.default.temporaryDirectory.appending(path: "sift-reel-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let output: String = await Task.detached {
            let p = Process()
            p.executableURL = exe
            p.arguments = ["--no-warnings", "--no-playlist", "--no-progress", "-f", "ba/b",
                           "-o", dir.appending(path: "audio.%(ext)s").path(percentEncoded: false), url]
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            do { try p.run() } catch { return "" }
            let errors = Task.detached { String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) }
            let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            return text + "\n" + (await errors.value)
        }.value
        let lower = output.lowercased()
        if lower.contains("rate-limit") || lower.contains("429") || lower.contains("login required") {
            try? FileManager.default.removeItem(at: dir)
            await HostGate.shared.pause(gate, seconds: 3600)
            return .throttled
        }
        let file = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?.first
        guard let file else { try? FileManager.default.removeItem(at: dir); return .none }
        return .audio(file)
    }

    static func install() async -> String? {
        await TranscriptTool.install(package: "yt-dlp")
    }
}

/// On-device speech recognition where macOS has the language; Apple's
/// speech service otherwise.
enum ReelSpeech {
    static func authorize() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
    }

    /// The language of the caption picks the recognizer. English otherwise.
    static func locale(for hint: String?) -> Locale {
        let r = NLLanguageRecognizer()
        r.processString(hint ?? "")
        let map: [NLLanguage: String] = [.portuguese: "pt-BR", .spanish: "es-ES", .german: "de-DE",
                                         .dutch: "nl-NL", .french: "fr-FR", .italian: "it-IT"]
        return Locale(identifier: r.dominantLanguage.flatMap { map[$0] } ?? "en-US")
    }

    @MainActor
    static func transcribe(_ file: URL, hint: String?) async -> String? {
        guard let recognizer = SFSpeechRecognizer(locale: locale(for: hint)), recognizer.isAvailable else { return nil }
        let request = SFSpeechURLRecognitionRequest(url: file)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        return await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            var done = false
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                guard !done else { return }
                if let result, result.isFinal {
                    done = true
                    c.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    done = true
                    c.resume(returning: nil)
                }
            }
            _ = task
        }
    }
}
