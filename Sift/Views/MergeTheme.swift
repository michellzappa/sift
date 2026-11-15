import SwiftUI

/// "Merge Into" for a theme: a menu of the other themes, then a confirmation
/// that says what moves. Used in the sidebar and in Settings > Themes.
struct MergeThemeMenu: View {
    @Environment(AppModel.self) private var model
    let theme: String
    @Binding var pending: MergeRequest?

    var body: some View {
        Menu("Merge Into") {
            ForEach(model.themes.map(\.name).filter { $0 != theme }.sorted(), id: \.self) { other in
                Button(other) { pending = MergeRequest(from: theme, into: other) }
            }
        }
    }
}

struct MergeRequest: Identifiable {
    let from: String
    let into: String
    var id: String { from + "→" + into }
}

extension View {
    /// The confirmation for a merge picked from `MergeThemeMenu`.
    func mergeConfirmation(_ pending: Binding<MergeRequest?>, model: AppModel) -> some View {
        alert(pending.wrappedValue.map { "Merge \"\($0.from)\" into \"\($0.into)\"?" } ?? "",
              isPresented: Binding(get: { pending.wrappedValue != nil }, set: { if !$0 { pending.wrappedValue = nil } }),
              presenting: pending.wrappedValue) { r in
            Button("Merge") { model.mergeTheme(r.from, into: r.into) }
            Button("Cancel", role: .cancel) {}
        } message: { r in
            Text("\(model.count(r.from)) links move to \(r.into), with their notes and history. \(r.from) is removed. To split them again, move links by hand.")
        }
    }
}
