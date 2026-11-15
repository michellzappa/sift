import SwiftUI

/// Every single-key shortcut, from `KeyMap.bindings` (the same list the keys
/// run from). Opened with ? or Help > Keyboard Shortcuts.
struct ShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts").font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                          alignment: .leading, spacing: 22) {
                    ForEach(KeyMap.groups, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(group).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                            ForEach(unique(group)) { b in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    keys(b.keys).frame(width: 64, alignment: .leading)
                                    Text(b.title).font(.callout)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                Text("Keys work in the main window when no text field has focus. Space also opens the page beside a list; ⌘K opens Go to.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .frame(width: 640, height: 520)
    }

    /// One row per action: "j" and "n" do the same, so show them together.
    private func unique(_ group: String) -> [KeyBinding] {
        var seen: [String: Int] = [:]
        var out: [KeyBinding] = []
        for b in KeyMap.bindings where b.group == group {
            if let i = seen[b.title] { out[i].keys += " " + b.keys; continue }
            seen[b.title] = out.count
            out.append(b)
        }
        return out
    }

    private func keys(_ s: String) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(s.split(separator: " ").enumerated()), id: \.offset) { _, k in
                Text(k == "A" || k == "J" || k == "K" ? "⇧" + k : String(k))
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15)))
            }
        }
    }
}
