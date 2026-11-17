import SwiftUI

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
                    VStack(alignment: .leading, spacing: 3) {
                        // The unseen dot sits after the title.
                        HStack(alignment: .top, spacing: 6) {
                            Text(item.title)
                                .font(.body.weight(seen ? .regular : .semibold))
                                .foregroundStyle(seen ? .secondary : .primary)
                                .lineLimit(2)
                            if !seen { Circle().fill(Color.accentColor).frame(width: 8, height: 8).padding(.top, 6) }
                        }
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
