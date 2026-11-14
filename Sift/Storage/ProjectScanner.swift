import Foundation

/// Finds git repos under the projects folder, two levels deep, and reads a
/// one-line summary from each repo's README.md or AGENTS.md.
enum ProjectScanner {
    static func scan(root: URL) -> [Project] {
        let fm = FileManager.default
        var found: [Project] = []
        var seen = Set<String>()

        func visit(_ dir: URL, depth: Int) {
            guard depth <= 2,
                  let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            else { return }
            for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if fm.fileExists(atPath: child.appending(path: ".git").path(percentEncoded: false)) {
                    let name = child.lastPathComponent.lowercased()
                    if seen.insert(name).inserted {
                        found.append(Project(name: name, summary: summary(of: child), isRepo: true))
                    }
                } else {
                    visit(child, depth: depth + 1)
                }
            }
        }
        visit(root, depth: 1)
        return found.sorted { $0.name < $1.name }
    }

    private static func summary(of repo: URL) -> String {
        for file in ["README.md", "AGENTS.md"] {
            guard let text = try? String(contentsOf: repo.appending(path: file), encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("<") && !$0.hasPrefix("[!") && !$0.hasPrefix("```") }
            let joined = lines.prefix(3).joined(separator: " ")
                .replacingOccurrences(of: "#", with: "")
                .trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { return String(joined.prefix(240)) }
        }
        return ""
    }
}
