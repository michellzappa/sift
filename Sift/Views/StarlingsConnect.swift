import SwiftUI

/// Connects a Starlings workspace and adds its projects as destinations.
struct StarlingsConnect: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var origin: String?
    @State private var busy = false
    @State private var message: String?
    @State private var query = ""
    @State private var projects: [Starlings.Project] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect Starlings").font(.title3.weight(.semibold))
            if let origin {
                Text("Connected to \(URL(string: origin)?.host() ?? origin). Find the projects to send links to.")
                    .foregroundStyle(.secondary)
                TextField("Project name", text: $query)
                    .onSubmit { Task { await search(origin) } }
                List(projects) { p in
                    HStack {
                        Text(p.title)
                        Spacer()
                        if added(p, origin) {
                            Image(systemName: "checkmark").foregroundStyle(.secondary)
                        } else {
                            Button("Add") { add(p, origin) }
                        }
                    }
                }
                .frame(minHeight: 180)
            } else {
                Text("Your workspace address, for example bipe.starlings.work. Sift opens your browser to sign in; tick “Also write” there so Sift can file links.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("workspace.starlings.work", text: $address)
                    .onSubmit { Task { await connect() } }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Done") { dismiss() }
                if origin == nil {
                    Button("Connect") { Task { await connect() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(Starlings.origin(address) == nil || busy)
                } else {
                    Button("Search") { Task { await search(origin!) } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(query.isEmpty || busy)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func connect() async {
        guard let o = Starlings.origin(address) else { return }
        busy = true
        defer { busy = false }
        if Starlings.load(o) == nil {
            message = "Waiting for the sign-in in your browser…"
            do { try await Starlings.signIn(origin: o) } catch { message = error.localizedDescription; return }
        }
        message = nil
        origin = o
    }

    private func search(_ origin: String) async {
        busy = true
        defer { busy = false }
        do {
            projects = try await Starlings.projects(origin, matching: query)
            message = projects.isEmpty ? "No projects match." : nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func added(_ p: Starlings.Project, _ origin: String) -> Bool {
        model.destinations.contains { $0.kind == "starlings" && $0.config["origin"] == origin && $0.config["project"] == p.id }
    }

    private func add(_ p: Starlings.Project, _ origin: String) {
        model.addDestination(Destination(kind: "starlings", name: p.title, detail: URL(string: origin)?.host() ?? origin,
                                         config: ["origin": origin, "project": p.id]))
    }
}
