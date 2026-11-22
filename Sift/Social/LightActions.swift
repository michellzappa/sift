import AppKit
import SwiftUI

/// Who is signed in on Bluesky and Mastodon, read from the keychain. The
/// one copy the reader buttons and Settings watch.
@MainActor @Observable
final class SocialAccounts {
    static let shared = SocialAccounts()

    private(set) var blueskyHandle: String?
    private(set) var mastodonName: String?

    private init() { refresh() }

    func refresh() {
        blueskyHandle = Demo.isOn ? nil : BlueskyAccount.load()?.handle
        mastodonName = Demo.isOn ? nil : MastodonAccount.load()?.username
    }
}

/// The light actions above a Today or feed item in the reader pane (ADR
/// 0001, decision 5): Like and Save on Bluesky and Mastodon posts when the
/// person is signed in there, "Open in <App>" for Instagram, TikTok, X and
/// YouTube links. Off in demo mode.
struct LightActionsButtons: View {
    let pick: TodayPick

    private enum Post: Equatable {
        case bluesky(BlueskyAccount.PostState)
        case mastodon(MastodonAccount.StatusState)

        var liked: Bool {
            switch self {
            case .bluesky(let p): p.likeURI != nil
            case .mastodon(let s): s.favourited
            }
        }

        var saved: Bool {
            switch self {
            case .bluesky(let p): p.bookmarked
            case .mastodon(let s): s.bookmarked
            }
        }
    }

    @State private var post: Post?
    @State private var busy = false
    @State private var error: String?

    private var accounts: SocialAccounts { .shared }
    private var isBluesky: Bool { Networks.blueskyPost(pick.url) != nil && accounts.blueskyHandle != nil }
    private var isMastodon: Bool { Networks.isMastodonStatus(pick.url) && accounts.mastodonName != nil }

    var body: some View {
        if Demo.isOn {
            EmptyView()
        } else if let app = Networks.appName(for: pick.url) {
            Button("Open in \(app)") {
                if let url = URL(string: pick.url) { NSWorkspace.shared.open(url) }
            }
            .help("Opens the post in the \(app) app, or on its website.")
        } else if isBluesky || isMastodon {
            HStack(spacing: 6) {
                if let error {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help(error)
                }
                Button { Task { await toggle(like: true) } } label: {
                    Label(post?.liked == true ? "Liked" : "Like", systemImage: post?.liked == true ? "heart.fill" : "heart")
                }
                .help(isBluesky ? "Like this post on Bluesky." : "Like (favourite) this post on Mastodon.")
                Button { Task { await toggle(like: false) } } label: {
                    Label(post?.saved == true ? "Saved" : "Save", systemImage: post?.saved == true ? "bookmark.fill" : "bookmark")
                }
                .help(isBluesky ? "Save this post to your Bluesky bookmarks." : "Save this post to your Mastodon bookmarks.")
            }
            .disabled(busy || post == nil)
            .task(id: pick.url) { await load() }
        }
    }

    private func load() async {
        post = nil
        error = nil
        let url = pick.url
        do {
            if isBluesky { post = .bluesky(try await BlueskyAccount.post(url)) }
            else if isMastodon { post = .mastodon(try await MastodonAccount.status(url)) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func toggle(like: Bool) async {
        guard let post else { return }
        busy = true
        defer { busy = false }
        error = nil
        do {
            switch post {
            case .bluesky(let p):
                if like { self.post = .bluesky(try await BlueskyAccount.setLike(!post.liked, p)) }
                else { self.post = .bluesky(try await BlueskyAccount.setBookmark(!post.saved, p)) }
            case .mastodon(let s):
                if like { self.post = .mastodon(try await MastodonAccount.setFavourite(!post.liked, s)) }
                else { self.post = .mastodon(try await MastodonAccount.setBookmark(!post.saved, s)) }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Settings > Inputs: the Bluesky and Mastodon accounts for light actions.
struct SocialAccountsSettings: View {
    @State private var handle = ""
    @State private var appPassword = ""
    @State private var instance = ""
    @State private var busy = false
    @State private var blueskyError: String?
    @State private var mastodonError: String?

    private var accounts: SocialAccounts { .shared }

    var body: some View {
        Section {
            if let name = accounts.blueskyHandle {
                LabeledContent("Bluesky account") {
                    HStack {
                        Label("@\(name)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Button("Sign Out", role: .destructive) {
                            Task { await BlueskyAccount.signOut(); accounts.refresh() }
                        }
                    }
                }
            } else {
                TextField("Bluesky account", text: $handle, prompt: Text("name.bsky.social"))
                SecureField("App password", text: $appPassword, prompt: Text("xxxx-xxxx-xxxx-xxxx"))
                HStack {
                    Link("Make an app password", destination: URL(string: "https://bsky.app/settings/app-passwords")!)
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    Button("Sign In") { Task { await signInBluesky() } }
                        .disabled(handle.isEmpty || appPassword.isEmpty || busy || Demo.isOn)
                }
            }
            if let blueskyError { Text(blueskyError).font(.caption).foregroundStyle(.red) }
        } footer: {
            Text("App password, not your account password. Make one at bsky.app in Settings > Privacy and security > App passwords, and delete it there to cut Sift off. With it, Sift can like posts and save them to your private Bluesky bookmarks. Sift does not post, follow or read your messages. Sift keeps the app password in your Mac's keychain.")
                .foregroundStyle(.secondary)
        }

        Section {
            if let name = accounts.mastodonName {
                LabeledContent("Mastodon account") {
                    HStack {
                        Label("@\(name)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Button("Sign Out", role: .destructive) {
                            Task { await MastodonAccount.signOut(); accounts.refresh() }
                        }
                    }
                }
            } else {
                TextField("Mastodon account", text: $instance, prompt: Text("mastodon.social"))
                    .onSubmit { Task { await signInMastodon() } }
                HStack {
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    Button("Sign In") { Task { await signInMastodon() } }
                        .disabled(MastodonAccount.origin(instance) == nil || busy || Demo.isOn)
                }
            }
            if let mastodonError { Text(mastodonError).font(.caption).foregroundStyle(.red) }
        } footer: {
            Text("Sift opens your instance's sign-in page in the browser. It asks for four permissions: see your account name, look up a post from its link, like posts, and save posts to your bookmarks. Sift does not post, follow or read your messages. Sign Out takes the permission back.")
                .foregroundStyle(.secondary)
        }
    }

    private func signInBluesky() async {
        busy = true
        defer { busy = false }
        blueskyError = nil
        do {
            _ = try await BlueskyAccount.signIn(identifier: handle, appPassword: appPassword)
            appPassword = ""
            accounts.refresh()
        } catch {
            blueskyError = error.localizedDescription
        }
    }

    private func signInMastodon() async {
        guard MastodonAccount.origin(instance) != nil else { return }
        busy = true
        defer { busy = false }
        mastodonError = nil
        do {
            _ = try await MastodonAccount.signIn(instance)
            accounts.refresh()
        } catch {
            mastodonError = error.localizedDescription
        }
    }
}
