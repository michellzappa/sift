import HouseKitSparkle

/// Sift's updater: Sparkle through HouseKit (`SparkleUpdater`). The feed is
/// the appcast on the latest GitHub Release (Info.plist `SUFeedURL`), signed
/// with Sift's EdDSA key; the shared release workflow in michellzappa/housekit
/// writes it. Sparkle checks once a day, shows the release notes, verifies
/// the EdDSA signature and Apple's code signature, installs and relaunches.
///
/// Off in demo mode, and for copies outside /Applications (a build from
/// Xcode, a worktree or the mini never overwrites the installed app).
@MainActor
enum Updates {
    static let shared = SparkleUpdater(appName: "Sift", enabled: !Demo.isOn)
}
