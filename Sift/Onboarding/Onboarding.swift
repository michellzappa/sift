import AppKit
import SwiftUI

// MARK: - Adding an onboarding step
//
// 1. Create Sift/Onboarding/<Name>Step.swift with a struct that conforms to
//    `OnboardingStep`.
// 2. Add one instance to `Onboarding.steps` below, where it belongs in the
//    flow.
// A new id shows once to people who already finished the guide, under
// "New in Sift". Never rename an id: a renamed step shows again.

/// Where a step stands, with one line that says why.
struct OnboardingStatus: Equatable {
    enum Kind: Equatable { case done, available, blocked }
    let kind: Kind
    let reason: String

    static func done(_ reason: String) -> Self { .init(kind: .done, reason: reason) }
    static func available(_ reason: String) -> Self { .init(kind: .available, reason: reason) }
    static func blocked(_ reason: String) -> Self { .init(kind: .blocked, reason: reason) }
}

/// One page of the Setup Guide. A step reads and changes the app only
/// through `AppModel` (in the environment for its view), so it works the
/// same in the guide and anywhere else it is shown.
@MainActor
protocol OnboardingStep {
    associatedtype Body: View
    /// Stable and lowercase. Stored in `state.onboardingSeen`.
    var id: String { get }
    var title: String { get }
    /// An SF Symbol.
    var symbol: String { get }
    /// The user can skip it. Only Welcome is not optional.
    var isOptional: Bool { get }
    func status(_ model: AppModel) -> OnboardingStatus
    /// The step's content. It gets `AppModel` from the environment.
    @ViewBuilder var body: Body { get }
}

extension OnboardingStep {
    var isOptional: Bool { true }
    var view: AnyView { AnyView(body) }
}

@MainActor
enum Onboarding {
    /// The flow, in order.
    static let steps: [any OnboardingStep] = [
        WelcomeStep(),
        SourcesStep(),
        ChromeStep(),
        ClaudeStep(),
        LibraryStep(),
        ThemesStep(),
        SendStep(),
        DoneStep(),
    ]

    static var ids: [String] { steps.map(\.id) }
    static func step(_ id: String) -> (any OnboardingStep)? { steps.first { $0.id == id } }

    static let windowID = "setup-guide"
    /// Set before Sift relaunches itself for Full Disk Access, so the guide
    /// opens where the user left it.
    static let resumeKey = "onboarding.resumeStep"
}

/// The guide as it is open now: which steps, and where the user is.
struct OnboardingSession: Equatable {
    var stepIDs: [String]
    /// Only steps added since the user last saw the guide ("New in Sift").
    var isUpdate = false
    var index = 0
}

extension AppModel {
    /// The steps to show without being asked: the whole guide on first run,
    /// or only steps the user has not seen yet. nil when there is nothing new.
    func pendingOnboarding() -> OnboardingSession? {
        // The Setup Guide never opens by itself in demo mode.
        guard !Demo.isOn else { return nil }
        let seen = Set(state.onboardingSeen ?? [])
        let unseen = Onboarding.ids.filter { !seen.contains($0) }
        guard !unseen.isEmpty else { return nil }
        if seen.isEmpty { return fullOnboarding() }
        return OnboardingSession(stepIDs: unseen, isUpdate: true)
    }

    private func fullOnboarding() -> OnboardingSession {
        var session = OnboardingSession(stepIDs: Onboarding.ids)
        if let resume = UserDefaults.standard.string(forKey: Onboarding.resumeKey) {
            UserDefaults.standard.removeObject(forKey: Onboarding.resumeKey)
            session.index = session.stepIDs.firstIndex(of: resume) ?? 0
        }
        return session
    }

    /// Help > Setup Guide: the whole guide, where the user left it in this
    /// run, else from the start.
    func startSetupGuide() {
        if let current = onboarding, !current.isUpdate { return }
        onboarding = fullOnboarding()
    }

    /// Opens a step of the open guide by id.
    func onboardingGo(to id: String) {
        guard let i = onboarding?.stepIDs.firstIndex(of: id) else { return }
        onboarding?.index = i
    }

    /// The guide window closed (Esc or the close button). Its steps count as
    /// seen, so it does not open again on its own; the position stays for
    /// Help > Setup Guide.
    func onboardingClosed() {
        onboardingOpen = false
        if let ids = onboarding?.stepIDs { markOnboardingSeen(ids) }
    }

    /// The user finished the guide.
    func finishOnboarding() {
        if let ids = onboarding?.stepIDs { markOnboardingSeen(ids) }
        onboarding = nil
    }

    private func markOnboardingSeen(_ ids: [String]) {
        var seen = state.onboardingSeen ?? []
        for id in ids where !seen.contains(id) { seen.append(id) }
        if seen != state.onboardingSeen { state.onboardingSeen = seen }
    }

    /// Before the guide existed, state had no `onboardingSeen`. An install
    /// that already has themes or sorted links skips the first run.
    func settleOnboardingForExistingInstall() {
        guard state.onboardingSeen == nil else { return }
        let existing = !state.assignments.isEmpty || !state.extraProjects.isEmpty
        state.onboardingSeen = existing ? Onboarding.ids : []
    }

    /// Quits and opens Sift again. macOS sometimes applies a new Full Disk
    /// Access grant only to a fresh process.
    func relaunch(resumingAt stepID: String?) {
        if let stepID { UserDefaults.standard.set(stepID, forKey: Onboarding.resumeKey) }
        let path = Bundle.main.bundleURL.path(percentEncoded: false)
        let p = Process()
        p.executableURL = URL(filePath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }
}

// MARK: - The guide window

/// Step list with status dots on the left, the step on the right, and
/// Back, Skip and Continue below. Return continues, Esc closes.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow

    private var session: OnboardingSession { model.onboarding ?? OnboardingSession(stepIDs: Onboarding.ids) }
    private var steps: [any OnboardingStep] { session.stepIDs.compactMap(Onboarding.step) }
    private var index: Int { min(session.index, max(steps.count - 1, 0)) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                if let step = steps[safe: index] {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header(step)
                            step.view
                        }
                        .padding(28)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .id(step.id)
                }
                Divider()
                footer
            }
        }
        .frame(width: 780, height: 580)
        .background {
            // Esc closes the guide; the steps it showed count as seen.
            Button("Close") { dismissWindow(id: Onboarding.windowID) }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
        }
        .sheet(isPresented: .init(get: { model.themeProposal != nil }, set: { if !$0 { model.themeProposal = nil } })) {
            ThemeReview().environment(model)
        }
        .onAppear {
            model.onboardingOpen = true
            if model.onboarding == nil { model.onboarding = model.pendingOnboarding() ?? OnboardingSession(stepIDs: Onboarding.ids) }
        }
        .onDisappear { model.onboardingClosed() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.isUpdate ? "New in Sift" : "Set Up Sift")
                .font(.headline)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                Button { model.onboarding?.index = i } label: {
                    HStack(spacing: 8) {
                        StatusDot(status: step.status(model))
                        Text(step.title)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background(i == index ? AnyShapeStyle(.selection.opacity(0.35)) : AnyShapeStyle(.clear),
                                in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 24)
        .frame(width: 200)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.background.secondary)
    }

    private func header(_ step: any OnboardingStep) -> some View {
        let status = step.status(model)
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: step.symbol)
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).font(.title2.weight(.semibold))
                if !status.reason.isEmpty {
                    Text(status.reason)
                        .font(.callout)
                        .foregroundStyle(status.kind == .blocked ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
            }
        }
    }

    /// Moves to step `i`. The value is computed before the write:
    /// `model.onboarding?.index = index + 1` starts the write to
    /// `onboarding` first, then `index` reads it, and Swift aborts on the
    /// overlapping access (the 0.4.1 Continue crash).
    private func go(_ i: Int) {
        let target = i
        model.onboarding?.index = target
    }

    private var footer: some View {
        let step = steps[safe: index]
        let isLast = index >= steps.count - 1
        let blocked = step?.status(model).kind == .blocked
        return HStack {
            Button("Back") { go(index - 1) }
                .disabled(index == 0)
            Spacer()
            if step?.isOptional == true, !isLast {
                Button("Skip") { go(index + 1) }
            }
            Button(isLast ? "Done" : "Continue") {
                if isLast {
                    model.finishOnboarding()
                    dismissWindow(id: Onboarding.windowID)
                } else {
                    go(index + 1)
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(blocked && !isLast)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }
}

/// Green check for done, an open ring for available, a dash for blocked.
struct StatusDot: View {
    let status: OnboardingStatus

    var body: some View {
        Group {
            switch status.kind {
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .available: Image(systemName: "circle").foregroundStyle(.tint)
            case .blocked: Image(systemName: "minus.circle").foregroundStyle(.secondary)
            }
        }
        .frame(width: 16)
        .help(status.reason)
    }
}

/// A short paragraph with an icon, used by several steps.
struct OnboardingNote: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Help > Setup Guide…, which opens the guide window from anywhere.
struct SetupGuideCommand: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Setup Guide…") {
            model.startSetupGuide()
            openWindow(id: Onboarding.windowID)
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
