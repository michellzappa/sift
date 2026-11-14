import SwiftUI

/// Connects a Starlings workspace as one destination, "Starlings: <Name>".
/// Sent links become your link saves in that workspace's Docs (Links).
struct StarlingsConnect: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect Starlings").font(.title3.weight(.semibold))
            Text("Type your workspace name, for example bipe, or a full address. Sift opens your browser so you can sign in. Tick \"Also write\" there so Sift can save links.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("workspace", text: $address)
                .onSubmit { Task { await connect() } }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Connect") { Task { await connect() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(Starlings.origin(address) == nil || busy)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func connect() async {
        guard !Demo.isOn else { message = Demo.offMessage; return }
        guard let o = Starlings.origin(address) else { return }
        busy = true
        defer { busy = false }
        if Starlings.load(o) == nil {
            message = "Waiting for the sign-in in your browser…"
            do { try await Starlings.signIn(origin: o) } catch { message = error.localizedDescription; return }
        }
        model.addDestination(await Starlings.destination(for: o))
        dismiss()
    }
}
