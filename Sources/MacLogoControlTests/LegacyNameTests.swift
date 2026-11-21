import Foundation
@testable import MacLogoControlCore

/// Moving the settings from the app's old identity, LogoLight (`LegacyName`).
@MainActor
func legacyNameTests(_ t: TestHarness) {
    t.test("the old app's settings are all moved") {
        let old: [String: Any] = ["Brightness": 0.42, "FollowsBattery": true, "MorseText": "SOS",
                                  "DisplayBrightnessMapping": [[0.0, 12.5]]]
        let moved = LegacyName.settingsToMove(from: old, alreadySetIn: [])
        t.expectEqual(Set(moved.keys), Set(old.keys))
        t.expectEqual(moved["Brightness"] as? Double, 0.42)
    }

    t.test("macOS's own keys stay behind") {
        let old: [String: Any] = ["Brightness": 1.0, "AppleLanguages": ["en"], "NSWindow Frame Panel": "{{0, 0}}",
                                  "com.apple.security.application-groups": ["x"], "MorseLoops": false]
        let moved = LegacyName.settingsToMove(from: old, alreadySetIn: [])
        t.expectEqual(Set(moved.keys), ["Brightness", "MorseLoops"])
    }

    t.test("a setting the renamed app already has isn't overwritten") {
        // Someone who ran the renamed build and moved its slider before updating keeps their choice.
        let old: [String: Any] = ["Brightness": 0.2, "Effect": "breathe"]
        let moved = LegacyName.settingsToMove(from: old, alreadySetIn: ["Brightness"])
        t.expectEqual(Set(moved.keys), ["Effect"])
    }

    t.test("the move happens once") {
        // Throwaway domains of their own, so no real preference is touched.
        let suite = "app.logolight.tests.legacyName.\(ProcessInfo.processInfo.processIdentifier)"
        let old = UserDefaults(suiteName: suite)!
        let fresh = UserDefaults(suiteName: suite + ".new")!
        fresh.removePersistentDomain(forName: suite + ".new")
        old.set(0.75, forKey: "Brightness")
        old.set([[0.0, 12.5]], forKey: "DisplayBrightnessMapping")

        let keys = LegacyName.moveSettings(into: fresh, from: old, suite: suite)
        t.expectEqual(keys, ["Brightness", "DisplayBrightnessMapping"])
        t.expectEqual(fresh.double(forKey: "Brightness"), 0.75)
        t.expectEqual(fresh.object(forKey: LegacyName.movedKey) != nil, true)

        // A second launch moves nothing, even after the old app's settings changed.
        old.set(0.1, forKey: "Brightness")
        t.expectEqual(LegacyName.moveSettings(into: fresh, from: old, suite: suite), [])
        t.expectEqual(fresh.double(forKey: "Brightness"), 0.75)

        // And an app with no predecessor moves nothing.
        let nothing = UserDefaults(suiteName: suite + ".empty")!
        t.expectEqual(LegacyName.moveSettings(into: nothing, from: UserDefaults(suiteName: suite + ".missing"),
                                             suite: suite + ".missing"), [])
        t.expectEqual(nothing.object(forKey: LegacyName.movedKey) == nil, true)

        old.removePersistentDomain(forName: suite)
        fresh.removePersistentDomain(forName: suite + ".new")
        nothing.removePersistentDomain(forName: suite + ".empty")
    }

    t.test("the old bundle ID is the one LogoLight used") {
        t.expectEqual(LegacyName.oldBundleID, "app.logolight.LogoLight")
        // The port and the extension are named off the app's own ID, so nothing else has to change.
        t.expectEqual(ControlLink.portName(forApp: "app.logolight.MacLogoControl"),
                      "app.logolight.MacLogoControl.control")
    }
}
