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

    /// The gate key for YouTube audio, apart from YouTube's captions.
    static let youTubeGate = "audio.youtube.com"

    /// Downloads the audio track of one reel or video into a temporary
    /// folder. M4A first: macOS speech recognition does not read WebM/Opus.
    static func audio(for url: String, gate: String = gate) async -> Outcome {
        guard let exe = executable else { return .none }
        guard await HostGate.shared.admit(gate) else { return .throttled }
        let dir = FileManager.default.temporaryDirectory.appending(path: "sift-reel-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let output: String = await Task.detached {
            let p = Process()
            p.executableURL = exe
            p.arguments = ["--no-warnings", "--no-playlist", "--no-progress", "-f", "ba[ext=m4a]/ba/b",
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
    /// - Parameter onDeviceOnly: long audio (whole videos) needs recognition
    ///   on this Mac; Apple's server recognition stops after about a minute.
    static func transcribe(_ file: URL, hint: String?, onDeviceOnly: Bool = false) async -> String? {
        guard let recognizer = SFSpeechRecognizer(locale: locale(for: hint)), recognizer.isAvailable else { return nil }
        if onDeviceOnly, !recognizer.supportsOnDeviceRecognition { return nil }
        let request = SFSpeechURLRecognitionRequest(url: file)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        // Recognition can end without a final result or an error (no speech,
        // a stalled service). A deadline makes sure the queue moves on.
        let seconds = await Self.duration(of: file)
        let deadline = max(90, seconds * 3)
        let once = Once<String?>()
        return await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    once.run { c.resume(returning: result.bestTranscription.formattedString) }
                } else if error != nil {
                    once.run { c.resume(returning: nil) }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + deadline) {
                once.run {
                    task.cancel()
                    c.resume(returning: nil)
                }
            }
        }
    }

    static func duration(of file: URL) async -> Double {
        guard let time = try? await AVURLAsset(url: file).load(.duration) else { return 60 }
        let s = time.seconds
        return s.isFinite && s > 0 ? s : 60
    }
}

/// Runs a closure at most once, from any thread.
final class Once<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}
