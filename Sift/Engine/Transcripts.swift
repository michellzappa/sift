import Foundation

/// YouTube transcripts through the open-source `youtube-transcript-api`
/// tool (MIT), when it is installed. Sift calls it like it calls `claude`:
/// an optional outside tool, so the app itself keeps no dependencies.
///
/// The tool reads YouTube's public caption data in a way YouTube has not
/// sanctioned; it can stop working, and YouTube throttles it at volume. Sift
/// paces it (see `HostGate`) and stops for an hour when YouTube refuses.
enum TranscriptTool {
    /// Sift's own install location, then the usual places.
    static var executable: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            installFolder.appending(path: "venv/bin/youtube_transcript_api"),
            home.appending(path: ".local/bin/youtube_transcript_api"),
            URL(filePath: "/opt/homebrew/bin/youtube_transcript_api"),
            URL(filePath: "/usr/local/bin/youtube_transcript_api"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
    }

    static var installFolder: URL { StateFile.url.deletingLastPathComponent().appending(path: "tools", directoryHint: .isDirectory) }

    enum Outcome: Sendable { case transcript(String), none, throttled }

    static func videoID(_ url: String) -> String? {
        guard let u = URL(string: url), let host = u.host()?.lowercased() else { return nil }
        if host == "youtu.be" { return u.pathComponents.dropFirst().first }
        guard host.hasSuffix("youtube.com") else { return nil }
        return URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
    }

    /// Fetches one transcript as plain text, in the first available of the
    /// listed languages.
    static func fetch(_ videoID: String) async -> Outcome {
        guard let exe = executable else { return .none }
        guard await HostGate.shared.admit("transcripts.youtube.com") else { return .throttled }
        // Read the pipes while the tool writes: a transcript is often larger
        // than the pipe buffer, and reading only after exit would deadlock.
        let output: String = await Task.detached {
            let p = Process()
            p.executableURL = exe
            p.arguments = [videoID, "--languages", "en", "pt", "es", "de", "nl", "fr", "it", "--format", "text"]
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
        if lower.contains("too many requests") || lower.contains("ipblocked") || lower.contains("requestblocked") || lower.contains("429") {
            await HostGate.shared.pause("transcripts.youtube.com", seconds: 3600)
            return .throttled
        }
        if lower.contains("could not retrieve a transcript") || lower.contains("transcriptsdisabled") || lower.contains("notranscriptfound") {
            return .none
        }
        let text = tidy(output)
        return text.count > 200 ? .transcript(text) : .none
    }

    /// Caption lines become paragraphs; ">>" speaker changes start new ones.
    static func tidy(_ raw: String) -> String {
        var paragraphs: [String] = []
        var current = ""
        for line in raw.components(separatedBy: .newlines) {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { continue }
            if l.hasPrefix(">>") {
                if !current.isEmpty { paragraphs.append(current) }
                current = String(l.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else {
                current += current.isEmpty ? l : " " + l
                if current.count > 900, l.hasSuffix(".") { paragraphs.append(current); current = "" }
            }
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs.joined(separator: "\n\n")
    }

    /// Installs the tool into Sift's own folder: a Python virtual environment
    /// with `youtube-transcript-api`. Needs Python 3 on the Mac.
    static func install(package: String = "youtube-transcript-api") async -> String? {
        let python = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let python else { return "Python 3 was not found." }
        let venv = installFolder.appending(path: "venv").path(percentEncoded: false)
        try? FileManager.default.createDirectory(at: installFolder, withIntermediateDirectories: true)
        for args in [[python, "-m", "venv", venv], [venv + "/bin/pip", "install", "-q", "--disable-pip-version-check", package]] {
            let status: Int32 = await withCheckedContinuation { c in
                let p = Process()
                p.executableURL = URL(filePath: args[0])
                p.arguments = Array(args.dropFirst())
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                p.terminationHandler = { c.resume(returning: $0.terminationStatus) }
                do { try p.run() } catch { c.resume(returning: -1) }
            }
            if status != 0 { return "Installing \(package) failed." }
        }
        return nil
    }
}
