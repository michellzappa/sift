import SwiftUI

/// One custom lane: its items in the same list and reader as Today.
struct LaneView: View {
    @Environment(AppModel.self) private var model
    let lane: Lane

    var body: some View {
        let picks = model.laneItems(lane)
        OfferedList(picks: picks, header: HStack {
            Text(lane.rule).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("Edit…") { model.editingLane = lane }.controlSize(.small)
        }.padding(.horizontal, 14).padding(.vertical, 8),
        empty: ContentUnavailableView("Nothing in this lane", systemImage: "line.3.horizontal.decrease.circle",
                                      description: Text("No item of your feeds from the last \(Int(Lanes.days)) days matches \(lane.rule).")))
        .navigationTitle(lane.name)
        .navigationSubtitle("\(picks.filter { !model.isSeen($0.url) }.count) new · last \(Int(Lanes.days)) days")
        .toolbar { ToolbarItem(placement: .principal) { ModePicker() } }
    }
}

/// New or edit a lane, with a live count.
struct LaneEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var lane: Lane

    var body: some View {
        let count = model.laneItems(lane).count
        VStack(alignment: .leading, spacing: 14) {
            Text(model.state.lanes.contains { $0.id == lane.id } ? "Edit Lane" : "New Lane").font(.title3.weight(.semibold))
            Text("A lane shows the items of your feeds from the last \(Int(Lanes.days)) days that match every part you set, newest first. It ends after \(Lanes.limit).")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("Name", text: $lane.name)
                TextField("Words", text: $lane.words, prompt: Text("agents, evals, \"small language models\""))
                Picker("Folder", selection: $lane.folder) {
                    Text("Any").tag(String?.none)
                    ForEach(model.feedFolders, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Picker("Theme", selection: $lane.theme) {
                    Text("Any").tag(String?.none)
                    ForEach(model.themes.map(\.name), id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Picker("Type", selection: $lane.mode) {
                    Text("Any").tag(String?.none)
                    ForEach(ReadingMode.allCases, id: \.self) { Text($0.title).tag(String?.some($0.rawValue)) }
                }
            }
            .formStyle(.grouped)
            Text("\(count) item\(count == 1 ? "" : "s") match now: \(lane.rule).").font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if lane.name.trimmingCharacters(in: .whitespaces).isEmpty { lane.name = lane.terms.first?.capitalized ?? "Lane" }
                    model.saveLane(lane)
                    model.navigationRequest = .lane(lane.id)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
