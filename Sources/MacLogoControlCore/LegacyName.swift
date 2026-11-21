import Foundation

/// The app was **LogoLight** up to 1.4.0. The rename also gave it a new bundle identifier, and macOS
/// files an app's settings under its bundle identifier, so its brightness, effect and switches would
/// all read as unset on the first launch. This moves them across, once, from the old preferences.
///
/// Two things can't be moved and are said so in the release's notes:
/// - **Launch at Login**, which the system registers per bundle identifier: it has to be switched on
///   again (the panel reads the real registration, so it shows off rather than lying).
/// - A **Control Center control** already placed. It names the old extension, which is gone; the new
///   one has to be added again in Control Center's Edit Controls.
public enum LegacyName {
    /// The bundle identifier the app had until 1.4.0.
    public static let oldBundleID = "app.logolight.LogoLight"

    /// Set here once the settings have been moved, so it happens once and a later change isn't
    /// overwritten by the old preferences.
    static let movedKey = "SettingsMovedFromLogoLight"

    /// Keys the old domain holds that aren't the app's own settings: macOS's window frames,
    /// sandbox bookkeeping and the like, all of which mean nothing to this app.
    static func isAppSetting(_ key: String) -> Bool {
        key != movedKey && !key.hasPrefix("NS") && !key.hasPrefix("Apple") && !key.hasPrefix("com.apple")
    }

    /// What to copy over: the old app's own settings, skipping what this app already has a value for
    /// (someone may have used the renamed build before the move ran) and its bookkeeping.
    public static func settingsToMove(from old: [String: Any], alreadySetIn current: Set<String>) -> [String: Any] {
        old.filter { key, _ in isAppSetting(key) && !current.contains(key) }
    }

    /// Copies the old app's settings into this app's, once. Returns the keys moved, for the log.
    /// Does nothing at all without the old preferences — a fresh install has nothing to move.
    /// `suite` is `old`'s suite name, which is where its own keys are kept.
    @discardableResult
    public static func moveSettings(into current: UserDefaults = .standard,
                                    from old: UserDefaults? = UserDefaults(suiteName: oldBundleID),
                                    suite: String = oldBundleID) -> [String] {
        guard current.object(forKey: movedKey) == nil,
              let old, let domain = old.persistentDomain(forName: suite), !domain.isEmpty else { return [] }
        let moved = settingsToMove(from: domain,
                                   alreadySetIn: Set(current.dictionaryRepresentation().keys))
        for (key, value) in moved { current.set(value, forKey: key) }
        current.set(true, forKey: movedKey)
        return moved.keys.sorted()
    }
}
