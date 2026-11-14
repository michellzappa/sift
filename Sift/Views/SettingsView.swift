import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            SortingSettings().tabItem { Label("Sorting", systemImage: "sparkles") }
            ThemeSettings().tabItem { Label("Themes", systemImage: "circle.hexagongrid") }
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
                TextField("X app Client ID", text: $model.state.xClientID, prompt: Text("From the X Developer Console"))
                    .disabled(model.xConnected)
                HStack {
                    if model.xConnected {
                        Label("Connected as @\(model.state.xUsername ?? "")", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Spacer()
                        Button("Sync Bookmarks") { Task { await model.syncXBookmarks() } }.disabled(model.xBusy)
                        Button("Disconnect", role: .destructive) { model.disconnectX() }
                    } else {
                        Button("Connect X Account") { Task { await model.connectX() } }
                            .disabled(model.state.xClientID.isEmpty || model.xBusy)
                        if model.xBusy { ProgressView().controlSize(.small) }
                    }
                }
                if let error = model.xError { Text(error).font(.caption).foregroundStyle(.red) }
            } header: {
                Text("X API (optional, paid)")
            } footer: {
                Text("Shows X posts natively and brings in your bookmarks, using your own X developer app. Create a Native App in the X Developer Console with callback URL \(XAuth.redirectURI) and the scopes tweet.read, users.read, bookmark.read and offline.access, then paste its Client ID here. X bills your developer account per post read (about $0.005). Sift caches posts and refreshes a post when it is older than a week.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Tab database", value: CloudTabsReader.databaseURL.path(percentEncoded: false))
                Button("Open Full Disk Access") { AppModel.openFullDiskAccessSettings() }
            }
            Section {
                LabeledContent("Instagram export") {
                    HStack {
                        Text(model.state.instagramExportPath ?? "None")
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…") { model.chooseInstagramExport() }
                        if model.state.instagramExportPath != nil {
                            Button("Remove") { model.clearInstagramExport() }
                        }
                    }
                }
            } header: {
                Text("Sources")
            } footer: {
                Text(model.instagramError ?? "Instagram Saved reads saved posts and collections from a JSON data export (Accounts Center, Download your information). Choose the zip or the folder it unpacks to.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ThemeSettings: View {
    @Environment(AppModel.self) private var model
    @State private var newName = ""
    @State private var newSummary = ""
    @State private var editing: String?
    @State private var draft = ""

    var body: some View {
        Form {
            Section {
                if model.themes.isEmpty {
                    Text("No themes yet. Discover Themes reads all your links and proposes them.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.projects) { theme in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            if editing == theme.name {
                                TextField("Name", text: $draft)
                                    .onSubmit { model.renameTheme(theme.name, to: draft); editing = nil }
                            } else {
                                Text(theme.name)
                            }
                            if !theme.summary.isEmpty {
                                Text(theme.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer()
                        Text("\(model.count(theme.name))").monospacedDigit().foregroundStyle(.secondary)
                        Button { draft = theme.name; editing = theme.name } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                            .help("Rename")
                        Button(role: .destructive) { model.removeTheme(theme.name) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Delete the theme. Its links become unsorted.")
                    }
                }
            } header: {
                Text("Themes")
            } footer: {
                Button("Discover Themes Again") { Task { await model.discoverThemes() } }
                    .disabled(model.isDiscovering || model.isSorting)
            }
            Section("Add a theme by hand") {
                TextField("Name", text: $newName)
                TextField("What it is about (helps Claude sort)", text: $newSummary)
                Button("Add Theme") {
                    model.addTheme(name: newName, summary: newSummary)
                    newName = ""; newSummary = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
    }
}
