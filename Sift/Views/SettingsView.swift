import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            SortingSettings().tabItem { Label("Sorting", systemImage: "sparkles") }
            ProjectSettings().tabItem { Label("Projects", systemImage: "folder") }
        }
        .frame(width: 560, height: 440)
    }
}

private struct SortingSettings: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""
    @State private var hasKey = Keychain.readKey() != nil

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Sort with", selection: $model.state.backend) {
                    ForEach(Sorter.Backend.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } footer: {
                Text(model.state.backend == .claudeCode
                     ? (ClaudeCodeRunner.executable == nil ? "Claude Code was not found in ~/.local/bin or Homebrew." : "Uses your Claude Code login. No API key needed.")
                     : "Uses the API key below, billed to your Anthropic API account.")
                    .foregroundStyle(.secondary)
            }
            Section {
                SecureField("Anthropic API key", text: $key, prompt: Text(hasKey ? "Saved in the keychain" : "sk-ant-…"))
                HStack {
                    Button("Save Key") { Keychain.saveKey(key); key = ""; hasKey = Keychain.readKey() != nil }
                        .disabled(key.isEmpty)
                    if hasKey {
                        Button("Remove Key", role: .destructive) { Keychain.saveKey(""); hasKey = false }
                    }
                }
            } footer: {
                Text("Sift sends the title, URL and preview text of each unsorted tab, and your project names and descriptions, to Claude. The key stays in your login keychain.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Use X's embed data for post images (unofficial, may stop working)", isOn: .init(
                    get: { model.state.xSyndication },
                    set: { model.setXSyndication($0) }
                ))
            } header: {
                Text("Previews")
            } footer: {
                Text("Off: X posts show text only, from X's public oEmbed endpoint. On: Sift asks X's syndication endpoint first, which adds the post image and the author's avatar.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Tab database", value: CloudTabsReader.databaseURL.path(percentEncoded: false))
                Button("Open Full Disk Access") { AppModel.openFullDiskAccessSettings() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProjectSettings: View {
    @Environment(AppModel.self) private var model
    @State private var newName = ""
    @State private var newSummary = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Projects folder") {
                HStack {
                    Text(model.state.projectsRoot).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { chooseRoot() }
                }
                Text("Sift finds git repos up to two levels down and reads each README for a description.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Projects without a repo") {
                ForEach(model.state.extraProjects) { p in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(p.name)
                            if !p.summary.isEmpty { Text(p.summary).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button(role: .destructive) { model.removeExtraProject(p.name) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                TextField("Name", text: $newName)
                TextField("What it is about (helps Claude sort)", text: $newSummary)
                Button("Add Project") {
                    model.addProject(name: newName, summary: newSummary)
                    newName = ""; newSummary = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Section("Repos") {
                ForEach(model.repoProjects) { p in
                    Toggle(isOn: .init(
                        get: { !model.state.hiddenProjects.contains(p.name) },
                        set: { model.setHidden(p.name, hidden: !$0) }
                    )) {
                        VStack(alignment: .leading) {
                            Text(p.name)
                            if !p.summary.isEmpty { Text(p.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.state.projectsRoot = url.path(percentEncoded: false)
        model.reload()
    }
}
