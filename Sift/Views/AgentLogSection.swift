import SwiftUI

/// The latest actions Claude took through sift-mcp (agent/log.jsonl).
struct AgentLogSection: View {
    struct Entry: Decodable, Identifiable {
        let at: Date
        let tool: String
        let status: String
        let text: String
        var id: String { "\(at.timeIntervalSince1970)\(tool)" }
    }
    @State private var entries: [Entry] = []

    var body: some View {
        Section {
            if entries.isEmpty {
                Text("Nothing yet.").foregroundStyle(.secondary)
            }
            ForEach(entries) { e in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: e.status == "failed" ? "xmark.circle" : e.status == "started" ? "clock" : "checkmark.circle")
                        .foregroundStyle(e.status == "failed" ? .orange : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.text.components(separatedBy: "\n").first ?? e.text).lineLimit(2)
                        Text("\(e.tool.replacingOccurrences(of: "_", with: " ")) · \(e.at.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("Recent actions by Claude")
                Spacer()
                Button("Refresh") { load() }.buttonStyle(.borderless).font(.caption)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let text = try? String(contentsOf: AgentFiles.log, encoding: .utf8) else { entries = []; return }
        entries = text.split(separator: "\n").suffix(30).reversed()
            .compactMap { try? AgentFiles.coder.1.decode(Entry.self, from: Data($0.utf8)) }
    }
}
