import AppKit
import LogoLightCore
import os
import WidgetKit

/// The menu bar icon and its menu, which starts with the control panel.
///
/// Click to open the menu; Option-click to toggle the logo straight away.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let controller: LogoController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    private let panel = ControlPanel(finish: StatusItemController.previewFinish,
                                     lid: StatusItemController.previewLid)
    private let panelItem = NSMenuItem()
    private let passwordlessItem = NSMenuItem()
    private var lidObserver: LidObserver?
    private let sleepBlocker = LidSleepBlocker()
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LogoLight", category: "lid")

    private var status = LogoStatus.unsupported
    /// Waiting for a password or `sudo` (the fallback path), or for the menu to close before a
    /// password dialog.
    private var isBusy = false
    /// The setting the switch asked for, while it's being applied. The panel and the icon show it
    /// straight away, rather than the setting, which only changes after the fade.
    private var requestedSetting: LogoIllumination?
    /// A flip made while a direct switch is being applied: the latest one, applied next.
    private var queuedSetting: LogoIllumination?
    private var switchTask: Task<Void, Never>?
    private var isMenuOpen = false
    /// What's waiting for the menu to close (see `whenMenuClosed(_:)`).
    private var afterMenuCloses: [@MainActor () -> Void] = []
    /// Picks up changes made elsewhere, e.g. from Terminal: every 10 s, or every second while the
    /// menu is open.
    private var refreshTimer: Timer?
    /// Watches the display's brightness while the logo follows it.
    private var displayBrightnessTimer: Timer?
    /// Redraws the live view at the display's frame rate while the menu is open.
    private var glowLink: CADisplayLink?
    /// Launch at Login and the sudoers rule, read when the menu opens and after they're changed,
    /// rather than on every refresh.
    private var isLaunchAtLoginEnabled = false
    private var isPasswordlessEnabled = false
    /// The menu bar icon's description and look, so it's only replaced when they change.
    private var iconSymbol: (description: String, isDimmed: Bool)?
    private var observers: [NSObjectProtocol] = []
    /// Reads whether the built-in display is awake, for screen changes.
    private let displayReader = LogoStatusReader()
    /// Whether the built-in display was awake at the last screen change (`nil` if unknown).
    private var wasBuiltInDisplayAwake: Bool?
    /// Answers the Control Center control (only in the app bundle, which has the control).
    private var controlServer: ControlLinkServer?
    /// What the control was last told to show, so it's only reloaded when that changes.
    private var controlState: ControlLink.State?
    /// Tells the controller when the battery may have changed, for the battery indicator.
    private var batteryObserver: BatteryObserver?
    /// Lends the logo to Codeman while it blinks it, and takes it back after (see `CodemanLoan`).
    private let loanWatcher: LoanWatcher
    /// Keeps the logo's brightness off the display's, should corebrightnessd lose the mapping that does
    /// it (see `LogoController.keepBrightnessUntied()`).
    private var mappingTimer: Timer?

    private static let effectDefaultsKey = "Effect"
    private static let brightnessDefaultsKey = "Brightness"
    private static let followsBatteryDefaultsKey = "FollowsBattery"
    private static let followsDisplayBrightnessDefaultsKey = "FollowsDisplayBrightness"
    /// The Charging switch: on, the logo breathes while the battery charges.
    private static let breathesWhileChargingDefaultsKey = "BreathesWhileCharging"
    /// The Morse message typed last, put back in the field at launch.
    private static let morseTextDefaultsKey = "MorseText"
    private static let previewFinishDefaultsKey = "PreviewFinish"

    private static let previewLidDefaultsKey = "PreviewLid"

    /// The finish the live view shows: the one picked in the panel, or else this Mac's own.
    private static var previewFinish: MacFinish {
        switch UserDefaults.standard.string(forKey: previewFinishDefaultsKey) {
        case "silver": .silver
        case "spaceBlack": .spaceBlack
        default: MacFinish.current() ?? .spaceBlack
        }
    }
    /// The lid size the live view shows: the one picked in the panel, or else this Mac's own.
    private static var previewLid: MacLid {
        switch UserDefaults.standard.string(forKey: previewLidDefaultsKey) {
        case "14": .fourteen
        case "16": .sixteen
        default: MacLid.current() ?? .sixteen
        }
    }
    /// The Morse loop switch: on, a message repeats until it's stopped.
    private static let morseLoopsDefaultsKey = "MorseLoops"
    private var morseLoops = UserDefaults.standard.bool(forKey: StatusItemController.morseLoopsDefaultsKey)
    /// Set when the user unchecks Disable Password, so the rule isn't installed again with the next password.
    private static let keepsPasswordDefaultsKey = "KeepsPassword"
    private static let lightsWithLidClosedDefaultsKey = "LightsWithLidClosed"

    init(controller: LogoController) {
        self.controller = controller
        loanWatcher = LoanWatcher(controller: controller)
        super.init()
        buildMenu()

        // Bring back the brightness and effect chosen last time. This also takes over from anything a
        // previous run left behind (e.g. a crash mid-effect), without relighting to full first.
        let defaults = UserDefaults.standard
        let brightness = defaults.object(forKey: Self.brightnessDefaultsKey) != nil
            ? defaults.double(forKey: Self.brightnessDefaultsKey) : nil
        let effect = defaults.string(forKey: Self.effectDefaultsKey).flatMap(LogoEffect.init(rawValue:))
        // Codeman may be blinking the logo already: then it's left to Codeman until it's done.
        loanWatcher.check()
        controller.start(brightness: brightness, effect: effect ?? .none,
                         followsBattery: defaults.bool(forKey: Self.followsBatteryDefaultsKey),
                         followsDisplayBrightness: defaults.bool(forKey: Self.followsDisplayBrightnessDefaultsKey),
                         lightsWithLidClosed: defaults.bool(forKey: Self.lightsWithLidClosedDefaultsKey),
                         breathesWhileCharging: defaults.bool(forKey: Self.breathesWhileChargingDefaultsKey))
        // Without direct control, the first password also turns on Disable Password, unless the user
        // has turned it off before.
        controller.autoEnablesPasswordless = !defaults.bool(forKey: Self.keepsPasswordDefaultsKey)
        controller.willPromptForPassword = { [weak self] in await self?.closeMenuForPasswordDialog() }
        observeDisplay()
        lidObserver = LidObserver { [weak self] in self?.lidDidChange() }
        // About once a minute, and when the Mac is plugged in or unplugged. The controller only reads the
        // battery while it's followed, or while the logo breathes when it charges, and only changes the
        // logo when the percentage, or whether it's charging, has changed; the panel's slider then shows
        // the new charge.
        batteryObserver = BatteryObserver { [weak self] in
            self?.controller.batteryDidChange()
            self?.updateMenu()
        }

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            // On the press, like the other menu bar items, not when the button comes back up.
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }

        readMenuSettings()
        refresh()
        scheduleDisplayBrightnessWatch()
        scheduleRefresh(every: 10)
        loanWatcher.onChange = { [weak self] in self?.refresh() }
        loanWatcher.start()
        // One key read from corebrightnessd every 10 s.
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.keepBrightnessUntied() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        mappingTimer = timer

        // (A debug build run from .build has no bundle ID, and no control.)
        if let bundleID = Bundle.main.bundleIdentifier {
            controlServer = ControlLinkServer(appBundleID: bundleID) { [weak self] request in
                self?.handleControl(request) ?? ControlLink.State(isOn: false, isAvailable: false)
            }
            // A control placed while the app wasn't running shows its last value until it's reloaded.
            updateControl(panelState)
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        panelItem.view = panel
        panel.onLogoSwitched = { [weak self] isOn in self?.setLogo(isOn ? .on : .off) }
        panel.onBrightnessChanged = { [weak self] in self?.setBrightness($0) }
        panel.onFollowsBatteryChanged = { [weak self] in self?.setFollowsBattery($0) }
        panel.onFollowsDisplayBrightnessChanged = { [weak self] in self?.setFollowsDisplayBrightness($0) }
        panel.onLightsWithLidClosedChanged = { [weak self] in self?.setLightsWithLidClosed($0) }
        panel.onLaunchAtLoginChanged = { [weak self] in self?.setLaunchAtLogin($0) }
        panel.onBreathesWhileChargingChanged = { [weak self] in self?.setBreathesWhileCharging($0) }
        panel.onEffectChosen = { [weak self] in self?.chooseEffect($0) }
        panel.onMorsePlay = { [weak self] in self?.playMorse($0) }
        panel.onMorseLoopsChanged = { [weak self] in self?.setMorseLoops($0) }
        panel.onMorseStop = { [weak self] in self?.stopMorse() }
        panel.onMorseTextChanged = { UserDefaults.standard.set($0, forKey: Self.morseTextDefaultsKey) }
        panel.onPreviewFinishChanged = { finish in
            UserDefaults.standard.set(finish == .silver ? "silver" : "spaceBlack", forKey: Self.previewFinishDefaultsKey)
        }
        panel.onPreviewLidChanged = { lid in
            UserDefaults.standard.set(lid == .fourteen ? "14" : "16", forKey: Self.previewLidDefaultsKey)
        }
        panel.setMorseText(UserDefaults.standard.string(forKey: Self.morseTextDefaultsKey) ?? "SOS")
        // So the play button turns back from stop as soon as a message sent once is done.
        controller.onMorseEnded = { [weak self] in self?.refresh() }
        // The character going out now, which the panel highlights in the notation.
        controller.onMorseCharacter = { [weak self] in self?.panel.setMorseCharacter($0) }
        controller.onRiseFromDark = { [weak self] in self?.showNewFrame() }
        controller.onSoundFailed = { [weak self] in self?.soundFailed($0) }

        // Checked when the sudoers rule is installed. Without direct control, the first password
        // installs it, so it's only needed once.
        passwordlessItem.title = "Disable Password"
        passwordlessItem.target = self
        passwordlessItem.action = #selector(togglePasswordless)
        passwordlessItem.toolTip = "Turn the logo on and off without entering your password. Uncheck to ask for it again."

        // No ⌘Q: its shortcut column would make the whole menu wider than the panel.
        let quitItem = NSMenuItem(title: "Quit LogoLight", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")

        menu.items = [
            panelItem,
            .separator(),
            passwordlessItem,
            .separator(),
            quitItem,
        ]
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            toggleLogo()
        } else {
            openMenu()
        }
    }

    func openMenu() {
        // Attach the menu only while it's open, so Option-click can bypass it.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        // The system's appearance, taken as the menu opens: dark or light, the panel follows it.
        panel.adopt(NSApp.effectiveAppearance)
        readMenuSettings()
        refresh()
        scheduleRefresh(every: 1)

        // The live view reads the real logo on every frame, in step with the display, so it's only
        // drawn while it's visible. (`.common` includes the menu's event-tracking mode.)
        panel.showGlow(controller.liveGlow)
        let link = panel.displayLink(target: self, selector: #selector(showLiveGlow))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        glowLink = link
    }

    @objc private func showLiveGlow(_ link: CADisplayLink) {
        panel.showGlow(controller.liveGlow)
    }

    func menuDidClose(_ menu: NSMenu) {
        // A brightness drag that closed the menu never reported its end; end it here, so the panel
        // applies the state it held back.
        panel.cancelBrightnessDrag()
        scheduleRefresh(every: 10)
        // The link keeps its target alive until it's invalidated.
        glowLink?.invalidate()
        glowLink = nil
        statusItem.menu = nil

        isMenuOpen = false
        let actions = afterMenuCloses
        afterMenuCloses = []
        // On the next turn, once the menu's tracking has ended.
        if !actions.isEmpty {
            DispatchQueue.main.async { MainActor.assumeIsolated { actions.forEach { $0() } } }
        }
    }

    /// Runs `action` once the menu is closed, closing it first if it's open. The password dialog
    /// blocks the app until it's answered, and an alert can't be used inside an open menu, so either
    /// would otherwise sit over a frozen menu.
    private func whenMenuClosed(_ action: @escaping @MainActor () -> Void) {
        guard isMenuOpen else { return action() }
        afterMenuCloses.append(action)
        menu.cancelTracking()
    }

    /// Just before a password dialog: closes the menu if it's open, and returns once it has. The
    /// controller calls it (`willPromptForPassword`) only when the dialog will really be shown.
    private func closeMenuForPasswordDialog() async {
        guard isMenuOpen else { return }
        // Meanwhile the switch looks disabled, as on the fallback path. A direct switch that has
        // fallen back to the dialog isn't busy otherwise.
        let marksBusy = !isBusy
        if marksBusy {
            isBusy = true
            updateMenu()
        }
        // Again if it was opened in the moment before this resumed.
        while isMenuOpen {
            await withCheckedContinuation { continuation in whenMenuClosed { continuation.resume() } }
        }
        if marksBusy {
            isBusy = false
            updateMenu()
        }
    }

    // MARK: - State

    private func refresh() {
        status = controller.status()
        updateMenu()
    }

    /// Runs `refresh()` every `interval` seconds, replacing the previous timer. It runs in the menu's
    /// event-tracking mode too.
    private func scheduleRefresh(every interval: TimeInterval) {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func readMenuSettings() {
        isLaunchAtLoginEnabled = LaunchAtLogin.isEnabled
        isPasswordlessEnabled = controller.isPasswordlessEnabled
    }

    private var panelState: PanelState {
        PanelState(status: status, requested: requestedSetting, canControlDirectly: controller.canControlDirectly,
                   canFollowSound: controller.canFollowSound, effect: controller.effect, brightness: controller.brightness,
                   followsBattery: controller.followsBattery,
                   followsDisplayBrightness: controller.followsDisplayBrightness,
                   breathesWhileCharging: controller.breathesWhileCharging,
                   lightsWithLidClosed: controller.lightsWithLidClosed,
                   showsLidClosedOption: controller.canLightWithLidClosed,
                   launchesAtLogin: isLaunchAtLoginEnabled, isBusy: isBusy, morse: controller.morse,
                   morseLoops: morseLoops)
    }

    /// Brings the icon, the panel and the menu items up to date with the last status and the choices.
    private func updateMenu() {
        let state = panelState
        updateIcon(state)
        panel.update(state)

        // Only needed when the logo can't be controlled directly; kept visible if a rule is
        // already installed, so it can be removed.
        passwordlessItem.isHidden = controller.canControlDirectly && !isPasswordlessEnabled
        passwordlessItem.state = isPasswordlessEnabled ? .on : .off
        passwordlessItem.isEnabled = status.isSupported && !isBusy
        updateSleepBlocker()
        updateControl(state)
    }

    private func controlState(_ state: PanelState) -> ControlLink.State {
        ControlLink.State(isOn: state.isOn, isAvailable: state.isSupported)
    }

    /// Has the Control Center control show what the switch shows, when that changes. (It asks over
    /// `ControlLink` when it's reloaded.)
    private func updateControl(_ state: PanelState) {
        let control = controlState(state)
        guard controlServer != nil, control != controlState else { return }
        controlState = control
        if #available(macOS 26, *) {
            ControlCenter.shared.reloadControls(ofKind: ControlLink.kind)
        }
    }

    /// A request from the Control Center control, handled as the menu's switch would, and answered
    /// as soon as the change has started.
    private func handleControl(_ request: ControlLink.Request) -> ControlLink.State {
        switch request {
        case .state:
            refresh()
        case .turnOn, .turnOff:
            // Only a change: switching to what the switch already shows would fade the logo out and
            // back in, and restart an effect. (A control can ask for that when its value is stale.)
            // Compared with the setting as it is now, not as the last refresh (up to 10 s ago) saw it.
            refresh()
            let turnsOn = request == .turnOn
            if status.isSupported, panelState.isOn != turnsOn { setLogo(turnsOn ? .on : .off) }
        }
        return controlState(panelState)
    }

    private func updateIcon(_ state: PanelState) {
        guard let button = statusItem.button,
              iconSymbol?.description != state.symbolDescription || iconSymbol?.isDimmed != state.isDimmed
        else { return }
        iconSymbol = (state.symbolDescription, state.isDimmed)
        let icon = MenuBarIcon.image(for: state)
        button.image = icon.image
        button.appearsDisabled = icon.isDimmed
        button.toolTip = "LogoLight: \(state.symbolDescription)\nOption-click to toggle"
    }

    // MARK: - Actions

    /// Option-click: flips what the switch shows.
    private func toggleLogo() {
        setLogo((requestedSetting ?? controller.status().setting ?? .on).toggled)
    }

    /// Turns the logo on or off. The switch shows it at once, and the rest of the panel follows.
    ///
    /// With direct control the switch stays usable while the logo fades. A flip made meanwhile is
    /// applied when the fade is done (only the latest, and only if it differs from what was just
    /// applied). Without direct control a password may be needed, and the switch is disabled until
    /// that's done. The menu closes only if the password dialog is shown: with the sudoers rule, it
    /// stays open.
    private func setLogo(_ target: LogoIllumination) {
        guard controller.canControlDirectly else {
            guard !isBusy else { return }
            requestedSetting = target
            perform { [controller] in try await controller.set(target) }
            return
        }
        requestedSetting = target
        refresh()
        guard switchTask == nil else {
            queuedSetting = target
            return
        }
        switchTask = Task { [weak self] in await self?.switchDirectly(to: target) }
    }

    private func switchDirectly(to target: LogoIllumination) async {
        var next: LogoIllumination? = target
        while let target = next {
            do {
                try await controller.set(target)
            } catch LogoLightError.cancelled {
                // The user closed the password dialog (corebrightnessd didn't take the change).
            } catch {
                report(error, title: "LogoLight couldn't make the change")
            }
            next = queuedSetting == target ? nil : queuedSetting
            queuedSetting = nil
        }
        switchTask = nil
        requestedSetting = nil
        refresh()
    }

    private func setBrightness(_ brightness: Double) {
        controller.setBrightness(brightness)
        UserDefaults.standard.set(brightness, forKey: Self.brightnessDefaultsKey)
    }

    /// Turns following the display's brightness on or off, and watches it while it's on: a screen that
    /// dims (the keyboard's keys, or macOS following the light) takes the logo with it.
    private func setFollowsDisplayBrightness(_ follows: Bool) {
        controller.setFollowsDisplayBrightness(follows)
        UserDefaults.standard.set(follows, forKey: Self.followsDisplayBrightnessDefaultsKey)
        scheduleDisplayBrightnessWatch()
        refresh()
    }

    private func scheduleDisplayBrightnessWatch() {
        displayBrightnessTimer?.invalidate()
        displayBrightnessTimer = nil
        guard controller.followsDisplayBrightness else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.controller.displayBrightnessDidChange() else { return }
                self.updateMenu()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayBrightnessTimer = timer
    }

    private func setFollowsBattery(_ follows: Bool) {
        controller.setFollowsBattery(follows)
        UserDefaults.standard.set(follows, forKey: Self.followsBatteryDefaultsKey)
        // The slider now shows the charge, or the chosen brightness again.
        updateMenu()
    }

    private func setBreathesWhileCharging(_ breathes: Bool) {
        controller.setBreathesWhileCharging(breathes)
        UserDefaults.standard.set(breathes, forKey: Self.breathesWhileChargingDefaultsKey)
        updateMenu()
    }

    private func chooseEffect(_ effect: LogoEffect) {
        controller.setEffect(effect)
        UserDefaults.standard.set(effect.rawValue, forKey: Self.effectDefaultsKey)
        refresh()
    }

    private func playMorse(_ text: String) {
        controller.playMorse(text, loops: morseLoops)
        refresh()
    }

    /// The loop switch, which also switches a message being sent, without restarting it.
    private func setMorseLoops(_ loops: Bool) {
        morseLoops = loops
        UserDefaults.standard.set(loops, forKey: Self.morseLoopsDefaultsKey)
        controller.setMorseLoops(loops)
        refresh()
    }

    private func stopMorse() {
        controller.stopMorse()
        refresh()
    }

    #if DEBUG
    /// For scripted UI checks: starts the panel's message, looping, so a screenshot can catch a group
    /// of the notation lit up. Keeps trying while the controller is still settling at launch.
    func debugSendMorse() {
        let text = UserDefaults.standard.string(forKey: Self.morseTextDefaultsKey) ?? "SOS"
        var tries = 0
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            tries += 1
            let started = self.controller.playMorse(text, loops: true)
            NSLog("LogoLight debug: morse start tried %d, started=%d", tries, started ? 1 : 0)
            if started { self.refresh(); timer.invalidate() }
            else if tries >= 20 { timer.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
    #endif

    /// The Sound effect couldn't start: the controller has dropped it, so the switch goes off and that's
    /// saved. Without permission to hear the sound, the alert can open the right System Settings pane.
    private func soundFailed(_ error: Error) {
        UserDefaults.standard.set(LogoEffect.none.rawValue, forKey: Self.effectDefaultsKey)
        refresh()
        whenMenuClosed { [weak self] in
            guard let self else { return }
            guard case .cannotListen = error as? SoundError else {
                return show(error, title: "LogoLight can't follow the sound")
            }
            NSApp.activate()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "LogoLight can't hear the sound"
            alert.informativeText = "To let the logo follow the sound your Mac plays, allow LogoLight under System Audio "
                + "Recording Only in System Settings › Privacy & Security › Screen & System Audio Recording, then turn "
                + "Sound on again. Nothing is recorded."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Has the display show a new frame, for corebrightnessd's display-ready gate: a rise from dark
    /// waits for one, up to 0.5 s with nothing changing on screen, which ran Morse code's letters
    /// together. The menu bar icon's opacity goes between 1 and 0.99, which can't be seen.
    private func showNewFrame() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LOGOLIGHT_NO_FRAME_NUDGE"] != nil { return }
        #endif
        guard let button = statusItem.button else { return }
        button.alphaValue = button.alphaValue < 1 ? 1 : 0.99
    }

    /// Returns the logo to normal before the app quits.
    func prepareToQuit() {
        sleepBlocker.set(false)
        controller.restoreNormalLighting()
    }

    /// Effects pause while the display or the Mac sleeps, or the built-in display goes away (the lid
    /// closed with an external display), and resume when it's back. The lid closing is handled as a
    /// sleep, then as a wake a moment later, once corebrightnessd has dealt with the lid: the logo is
    /// then lit again (Lit with Lid Closed) or left dark, also when it was held at a level, which the
    /// daemon alone leaves lit.
    private func observeDisplay() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.displayDidSleep()
                    Self.log.info("\(name.rawValue, privacy: .public)")
                    // The screens are said to sleep when the lid closes, too. Kept awake with the lid
                    // closed and no other display, the logo is lit again a moment later.
                    if name == NSWorkspace.screensDidSleepNotification, self.lightsLogoBehindClosedLid {
                        self.scheduleWake()
                    }
                }
            })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleWake() }
            })
        }
        wasBuiltInDisplayAwake = displayReader.isDisplayAwake()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensDidChange() }
        })
    }

    /// A display was added, removed or changed. Only the built-in display going or coming back counts,
    /// so connecting an external display doesn't restart an effect. `wasBuiltInDisplayAwake` is what
    /// was handled last, by this or by a sleep or wake.
    private func screensDidChange() {
        guard let isAwake = displayReader.isDisplayAwake() else { return }
        defer { wasBuiltInDisplayAwake = isAwake }
        guard let wasAwake = wasBuiltInDisplayAwake, wasAwake != isAwake else { return }
        if !isAwake {
            displayDidSleep()
            scheduleWake()
        } else if controller.animator?.isPlaying != true {
            // (An effect still playing means nothing was paused: handling a wake would restart it.)
            scheduleWake()
        }
    }

    /// The lid closed or opened. Without an external display nothing else says so: the app keeps the
    /// Mac awake (`updateSleepBlocker()`), and the built-in display stays online. It's handled as the
    /// built-in display going away or coming back.
    private func lidDidChange() {
        Self.log.info("lid \(self.displayReader.isLidClosed() == true ? "closed" : "open", privacy: .public), keeping awake: \(self.sleepBlocker.isHolding)")
        screensDidChange()
    }

    /// Whether the lid is closed with no other display, the Mac is kept awake for it, and the logo
    /// is to be lit.
    private var lightsLogoBehindClosedLid: Bool {
        sleepBlocker.isHolding && displayReader.isLidClosed() == true && displayReader.hasExternalDisplay() == false
    }

    /// Keeps the Mac awake when the lid closes, while Lit with Lid Closed is on, the logo is on and
    /// the Mac is on power: without an external display a closed lid puts it to sleep, and the logo
    /// goes dark with it. On battery it's left to sleep. Unplugged with the lid closed, lid sleep comes back
    /// on, and the Mac sleeps.
    private func updateSleepBlocker() {
        sleepBlocker.set(controller.lightsWithLidClosed && controller.canLightWithLidClosed
            && status.setting == .on && Battery.powerState()?.isPluggedIn == true)
    }

    /// The display or the Mac went to sleep.
    private func displayDidSleep() {
        controller.displayDidSleep()
        wasBuiltInDisplayAwake = false
    }

    /// Handles a wake once, a second after the last notification of it: a system wake posts more than
    /// one, and corebrightnessd relights the logo for the display itself first.
    private func scheduleWake() {
        controller.scheduleWake(after: 1) { [weak self] in
            guard let self else { return }
            wasBuiltInDisplayAwake = displayReader.isDisplayAwake()
            refresh()
        }
    }

    /// Unchecking removes the rule and remembers that, so the next password doesn't install it again.
    /// Checking it installs the rule; the password dialog's prompt says what it's for.
    @objc private func togglePasswordless() {
        let enable = !controller.isPasswordlessEnabled
        perform { [weak self, controller] in
            // Both always show the dialog. (Choosing the item has closed the menu already.)
            await self?.closeMenuForPasswordDialog()
            if enable {
                try await controller.enablePasswordless()
            } else {
                try controller.disablePasswordless()
            }
            // The controller has turned installing with the first password on or off. Saved only
            // now: a cancelled or failed dialog has thrown, and the earlier choice stands.
            UserDefaults.standard.set(!enable, forKey: Self.keepsPasswordDefaultsKey)
        }
    }

    /// The panel's Lid Closed switch: the logo stays lit when the lid closes, on power or with an
    /// external display, and on power the Mac is kept awake for it.
    private func setLightsWithLidClosed(_ lights: Bool) {
        controller.setLightsWithLidClosed(lights)
        UserDefaults.standard.set(lights, forKey: Self.lightsWithLidClosedDefaultsKey)
        updateMenu()
    }

    /// The panel's Launch at Login switch.
    private func setLaunchAtLogin(_ launch: Bool) {
        do {
            try LaunchAtLogin.setEnabled(launch)
        } catch {
            report(error, title: "Couldn't change Launch at Login")
        }
        isLaunchAtLoginEnabled = LaunchAtLogin.isEnabled
        updateMenu()
    }

    /// Runs a privileged operation, which may ask for a password, then refreshes and reports any
    /// error. It starts at once, with the switch disabled: the menu is closed just before a password
    /// dialog (`closeMenuForPasswordDialog()`), so `sudo` alone leaves it open.
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        updateMenu()
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                isBusy = false
                if switchTask == nil { requestedSetting = nil }
                // The rule may have been added or removed.
                isPasswordlessEnabled = controller.isPasswordlessEnabled
                refresh()
            }
            do {
                try await operation()
            } catch LogoLightError.cancelled {
                // The user closed the password dialog.
            } catch {
                report(error, title: "LogoLight couldn't make the change")
            }
        }
    }

    /// Shows an error once the menu has closed.
    private func report(_ error: Error, title: String) {
        whenMenuClosed { [weak self] in self?.show(error, title: title) }
    }

    private func show(_ error: Error, title: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
