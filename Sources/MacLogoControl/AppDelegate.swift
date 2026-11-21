import AppKit
import os
import MacLogoControlCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacLogoControl", category: "settings")
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // First launch under the new name: take over the settings saved under the old bundle ID,
        // before anything reads them.
        let moved = LegacyName.moveSettings()
        if !moved.isEmpty {
            Self.log.info("moved \(moved.count, privacy: .public) setting(s) from the old LogoLight preferences")
        }

        #if DEBUG
        // Draws the control panel to PNGs and quits, without touching the logo (debug builds only).
        if let folder = ProcessInfo.processInfo.environment["MACLOGOCONTROL_RENDER_PANEL"] {
            // The switches and the slider are AppKit's, and draw in the accent colour only in the key
            // window of the active app, so the app is brought forward for the moment the pictures take.
            // (It has no windows of its own; the renderer's are clear and out of the way.)
            NSApp.activate(ignoringOtherApps: true)
            waitUntilActive {
                PanelRenderer.render(to: folder)
                NSApp.terminate(nil)
            }
            return
        }
        #endif

        var makeController: @MainActor () -> LogoController = { LogoController.live() }
        #if DEBUG
        // A pretend logo, shown in the menu's live view, for Macs without one (debug builds only).
        if ProcessInfo.processInfo.environment["MACLOGOCONTROL_SIMULATE"] != nil { makeController = { LogoController.simulated() } }
        #endif
        statusItemController = StatusItemController(controller: makeController())

        #if DEBUG
        // Opens the menu on launch, for checking the UI without clicking (debug builds only).
        if ProcessInfo.processInfo.environment["MACLOGOCONTROL_OPEN_MENU"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.statusItemController?.openMenu()
            }
        }
        // And sends the Morse right away, so a screenshot can catch the notation following it. A timer
        // in the common modes, since the menu blocks the main queue while it's open.
        if ProcessInfo.processInfo.environment["MACLOGOCONTROL_SEND_ON_OPEN"] != nil {
            let send = Timer(timeInterval: 0.9, repeats: false) { [weak self] _ in
                self?.statusItemController?.debugSendMorse()
            }
            RunLoop.main.add(send, forMode: .common)
        }
        #endif
    }

    /// Runs `action` once the app is active, which is what its AppKit controls need to draw in the
    /// accent colour, or after a few seconds without it: the pictures then show them grey.
    private func waitUntilActive(deadline: Date = Date().addingTimeInterval(3), then action: @escaping @MainActor () -> Void) {
        guard !NSApp.isActive, Date() < deadline else { return action() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            MainActor.assumeIsolated { self.waitUntilActive(deadline: deadline, then: action) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItemController?.prepareToQuit()
    }
}
