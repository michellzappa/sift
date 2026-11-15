import SwiftUI

/// Lists of links, like mailboxes: themes with unseen counts, then the links
/// in a theme with unseen ones bold and dotted. Tap opens the link in the
/// in-app browser and marks it seen; swipe a row to switch seen and unseen.
struct ListsView: View {
    @Environment(Store.self) private var store
    @AppStorage("lists.unseenOnly") private var unseenOnly = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        LinkList(title: "All Unseen", items: store.deck.items, unseenOnly: true)
                    } label: {
                        row("All Unseen", symbol: "circle.inset.filled", color: .accentColor,
                            count: store.deck.items.filter { !store.isSeen($0.url) }.count)
                    }
                }
                Section("Themes") {
                    ForEach(store.deck.themes) { theme in
                        NavigationLink {
                            LinkList(title: theme.name, items: store.deck.items.filter { $0.theme == theme.name }, unseenOnly: unseenOnly)
                        } label: {
                            row(theme.name, symbol: "circle.fill", color: theme.color, count: store.unseenCount(theme: theme.name))
                        }
                    }
                }
            }
            .navigationTitle("Lists")
            .refreshable { store.sync() }
        }
    }

    private func row(_ title: String, symbol: String, color: Color, count: Int) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(color).font(.caption)
            Text(title).fontWeight(count > 0 ? .semibold : .regular)
            Spacer()
            if count > 0 { Text("\(count)").foregroundStyle(.secondary).monospacedDigit() }
        }
    }
}

struct LinkList: View {
    @Environment(Store.self) private var store
    let title: String
    let items: [Item]
    @State var unseenOnly: Bool
    @State private var browsing: Item?

    private var shown: [Item] { unseenOnly ? items.filter { !store.isSeen($0.url) } : items }

    var body: some View {
        List(shown) { item in
            let seen = store.isSeen(item.url)
            Button {
                guard URL(string: item.url) != nil else { return }
                store.setSeen([item], true, mode: "list")
                store.record(item, .open, mode: "list", position: 0)
                browsing = item
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(seen ? Color.clear : Color.accentColor).frame(width: 9, height: 9).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.body.weight(seen ? .regular : .semibold))
                            .foregroundStyle(seen ? .secondary : .primary)
                            .lineLimit(2)
                        Text([item.site, item.readTime].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        if !item.summary.isEmpty {
                            Text(item.summary).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    ItemImage(item: item, height: 56)
                        .frame(width: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .leading) {
                Button { store.setSeen([item], !seen, mode: "list") } label: {
                    Label(seen ? "Unseen" : "Seen", systemImage: seen ? "circle.fill" : "eye")
                }
                .tint(seen ? .accentColor : .gray)
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Unseen Only", isOn: $unseenOnly)
                    Button("Mark All as Seen") { store.setSeen(shown, true, mode: "list") }
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
            }
        }
        .sheet(item: $browsing) { InAppBrowser(url: URL(string: $0.url)!).ignoresSafeArea() }
    }
}
