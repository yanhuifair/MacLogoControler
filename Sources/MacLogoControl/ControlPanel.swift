import AppKit
import MacLogoControlCore
import Observation
import SwiftUI

/// The panel at the top of the menu, in SwiftUI, laid out and styled as System Settings is on macOS 27:
/// groups of rows on glass, a switch for the logo first, where it's easiest to reach, then a live view of
/// it, a brightness slider with the Battery and Charging switches under it, then a switch for each effect.
/// Everything below the live view is greyed out while the logo is off, and the slider is while the battery
/// sets the brightness.
///
/// It's an `NSHostingView` in the menu item's view: the menu is AppKit's, the panel inside it SwiftUI's.
@MainActor
final class ControlPanel: NSView {
    var onLogoSwitched: ((Bool) -> Void)?
    var onBrightnessChanged: ((Double) -> Void)?
    var onFollowsBatteryChanged: ((Bool) -> Void)?
    var onFollowsDisplayBrightnessChanged: ((Bool) -> Void)?
    var onBreathesWhileChargingChanged: ((Bool) -> Void)?
    var onLightsWithLidClosedChanged: ((Bool) -> Void)?
    var onLaunchAtLoginChanged: ((Bool) -> Void)?
    var onEffectChosen: ((LogoEffect) -> Void)?
    /// Play pressed (or Return in the field), with the message typed.
    var onMorsePlay: ((String) -> Void)?
    /// Play pressed while it shows stop: a message is being sent.
    var onMorseStop: (() -> Void)?
    /// The loop switch flipped: on, a message repeats until it's stopped.
    var onMorseLoopsChanged: ((Bool) -> Void)?
    /// The message edited (to remember it for next time).
    var onMorseTextChanged: ((String) -> Void)?
    /// The finish picked for the live view (to remember it for next time).
    var onPreviewFinishChanged: ((MacFinish) -> Void)?
    /// The lid size picked for the live view (to remember it for next time).
    var onPreviewLidChanged: ((MacLid) -> Void)?

    /// The panel is as wide and as tall as its content wants (the effect tabs across one row are what make
    /// it wide); this is the least it takes, so a panel without them still fits the menu's own items.
    static let width = PanelMetrics.minWidth

    private let model: PanelModel
    private let preview: LogoPreview
    private let host: NSHostingView<PanelContent>

    /// `finish` is the colour of this Mac's case and `lid` its screen size, which the live view copies.
    init(finish: MacFinish = .spaceBlack, lid: MacLid = .sixteen) {
        let preview = LogoPreview(finish: finish, lid: lid)
        let model = PanelModel(finish: finish, lid: lid)
        self.preview = preview
        self.model = model
        host = NSHostingView(rootView: PanelContent(model: model, preview: preview))
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 200))
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        // The panel is as big as what's in it: the hosting view is only pinned at the corner, and its own
        // size (what SwiftUI wants) is what the panel's frame is set to.
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: topAnchor),
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
        ])
        // The panel's callbacks are handed to it after it's built, so they're read when a control fires.
        model.onLogoSwitched = { [weak self] in self?.onLogoSwitched?($0) }
        model.onBrightnessChanged = { [weak self] in self?.onBrightnessChanged?($0) }
        model.onFollowsBatteryChanged = { [weak self] in self?.onFollowsBatteryChanged?($0) }
        model.onFollowsDisplayBrightnessChanged = { [weak self] in self?.onFollowsDisplayBrightnessChanged?($0) }
        model.onBreathesWhileChargingChanged = { [weak self] in self?.onBreathesWhileChargingChanged?($0) }
        model.onLightsWithLidClosedChanged = { [weak self] in self?.onLightsWithLidClosedChanged?($0) }
        model.onLaunchAtLoginChanged = { [weak self] in self?.onLaunchAtLoginChanged?($0) }
        model.onEffectChosen = { [weak self] in self?.onEffectChosen?($0) }
        model.onMorsePlay = { [weak self] in self?.onMorsePlay?($0) }
        model.onMorseStop = { [weak self] in self?.onMorseStop?() }
        model.onMorseLoopsChanged = { [weak self] in self?.onMorseLoopsChanged?($0) }
        model.onMorseTextChanged = { [weak self] in self?.onMorseTextChanged?($0) }
        model.onFinishChanged = { [weak self] in self?.onPreviewFinishChanged?($0) }
        model.onLidChanged = { [weak self] lid in
            self?.onPreviewLidChanged?(lid)
            // The other lid is a slightly different shape, and the panel is as tall as its content.
            DispatchQueue.main.async { [weak self] in self?.sizeToFitContent() }
        }
        model.onBrightnessDragEnded = { [weak self] in self?.brightnessDragEnded() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Top-down, as the menu's own items beside it are drawn, and as the picture of it is.
    override var isFlipped: Bool { true }

    /// Draws the panel in `appearance`: a menu item's view isn't always handed the menu window's, and
    /// SwiftUI then draws the panel in whichever appearance it fell back to rather than the system's.
    func adopt(_ appearance: NSAppearance?) {
        guard let appearance, appearance != self.appearance else { return }
        self.appearance = appearance
        host.appearance = appearance
    }

    /// Shows how brightly the logo is glowing right now, from 0 to 1.
    func showGlow(_ glow: Double) {
        preview.show(glow: glow)
    }

    func update(_ state: PanelState) {
        guard state != model.state else { return }
        // The app refreshes the panel every second while the menu's open. Laying the panel out under a
        // slider that's still tracking drops the drag (the thumb stops under the pointer), so hold the
        // newest state back while one is dragged and apply it when the slider lets go.
        if model.isDraggingBrightness { heldState = state; return }
        applyState(state)
    }

    /// The newest state that arrived mid-drag, applied when the slider lets go.
    private var heldState: PanelState?

    private func applyState(_ state: PanelState) {
        model.apply(state)
        // SwiftUI lays the new rows out on its next turn, and the menu item is as tall as the panel, so
        // it's sized once they're in.
        DispatchQueue.main.async { [weak self] in self?.sizeToFitContent() }
    }

    /// The slider let go: apply whatever the app said meanwhile.
    private func brightnessDragEnded() {
        guard let heldState else { return }
        self.heldState = nil
        applyState(heldState)
    }

    /// The menu closed with a drag still unreported (tracking ended without the slider saying so): end
    /// the drag, so the panel stops holding updates back.
    func cancelBrightnessDrag() {
        guard model.isDraggingBrightness else { return }
        model.dragBrightness(false)
    }

    /// Puts back the message typed last time.
    func setMorseText(_ text: String) {
        model.setMorseText(text)
    }

    /// Which character of the Morse message is sending now (nil: none). The notation under the field
    /// highlights it; the height can't change, so there's nothing to resize for.
    func setMorseCharacter(_ index: Int?) {
        model.morseCharacter = index
    }

    /// Lays the panel out for the state it was given, for drawing it into a picture: SwiftUI applies a
    /// change on the next turn of the run loop, so this waits for it, then sizes the panel to what it drew.
    func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        sizeToFitContent()
    }

    private func sizeToFitContent() {
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard size.width >= 1, size.height >= 1 else { return }
        if abs(frame.width - size.width) > 0.5 || abs(frame.height - size.height) > 0.5 {
            setFrameSize(size)
        }
    }

    /// The one-line labels in the panel's rows, for the renderer's check that they fit: SwiftUI truncates
    /// one that's too wide without saying so.
    var rowLabels: [String] {
        let state = model.state
        guard state.showsAdjustments else { return ["Mac Logo Control"] }
        return ["Mac Logo Control", "Battery", "Charging"]
            + LogoEffect.allCases.filter { $0 != .none && ($0 != .sound || state.showsSound) }.map(\.title)
    }
}

/// The numbers the panel is laid out with, the same as System Settings' where they can be.
private enum PanelMetrics {
    /// The least width the panel takes: enough for the menu's own items, and for the rows when the
    /// effects are hidden. It's as wide as its content wants, otherwise.
    static let minWidth: CGFloat = 172
    /// The live view's width — the lid's — and the least the panel takes with it in: that width and the
    /// margins either side, whatever the tabs and rows come to.
    static let liveViewWidth: CGFloat = 392
    static let widthWithLiveView: CGFloat = liveViewWidth + 2 * inset + 2 * iconInset
    /// Around the panel's contents (9 at the top, 6 at the bottom), and between its groups.
    static let inset: CGFloat = 6
    static let topInset: CGFloat = 9
    static let spacing: CGFloat = 6
    /// How far text outside the cards is indented, on both sides.
    static let textIndent: CGFloat = 12
    /// A row: as tall as a row in System Settings' lists, a little tighter for a menu.
    static let rowHeight: CGFloat = 36
    /// Where row text starts inside a card, and where the row icons start, and the width they're given.
    static let textColumn: CGFloat = 40
    static let iconInset: CGFloat = 8
    static let iconWidth: CGFloat = 24
    /// How far a control sits from the card's edge (the same as the icons), and the least room between it
    /// and its label. A hairline between rows stops this far short of the trailing edge too.
    static let controlInset: CGFloat = 8
    static let labelSpacing: CGFloat = 4
    /// The corners of the cards: rounder than before, as macOS 26 and later draw them. The tabs sit in
    /// one too, and their lozenge is inset by the bar's padding, so it's that much tighter.
    static let cardRadius: CGFloat = 13
    static let tabInset: CGFloat = 3
    static let tabRadius: CGFloat = cardRadius - tabInset
    /// Between one group and the next group's header, and between a header and its card.
    static let headerSpacing: CGFloat = 8
    static let headerToCard: CGFloat = 4
    /// How the brightness and the effects look while the logo is off, and how long they take to get there.
    static let greyedAlpha: Double = 0.4
    static let greying: Double = 0.22
}

/// What the panel shows, and what to tell the app when a control in it is used. The switches, the slider and
/// the loop button keep what the user just did until the app's state comes back, so they move under the
/// pointer rather than after the logo has faded.
@MainActor
@Observable
private final class PanelModel {
    /// Everything the panel decides from: what can be used, how the logo is doing, the message it shows.
    private(set) var state: PanelState
    var isOn: Bool
    var followsBattery: Bool
    var followsDisplayBrightness: Bool
    var breathesWhileCharging: Bool
    var lightsWithLidClosed: Bool
    var launchesAtLogin: Bool
    var effect: LogoEffect
    var loops: Bool
    /// The brightness the slider shows; not the app's while it's being dragged.
    var brightness: Double
    /// The message typed, which is the panel's while it's being edited.
    var morseText = "SOS"
    /// The character of the message being sent now, as the app reports it. nil: none, or not known yet.
    var morseCharacter: Int?
    /// The finish the live view is painted in: this Mac's, unless the user picked the other.
    var finish: MacFinish
    /// The lid the live view is shaped as: this Mac's, unless the user picked the other.
    var lid: MacLid

    var onLogoSwitched: ((Bool) -> Void)?
    var onBrightnessChanged: ((Double) -> Void)?
    var onFollowsBatteryChanged: ((Bool) -> Void)?
    var onFollowsDisplayBrightnessChanged: ((Bool) -> Void)?
    var onBreathesWhileChargingChanged: ((Bool) -> Void)?
    var onLightsWithLidClosedChanged: ((Bool) -> Void)?
    var onLaunchAtLoginChanged: ((Bool) -> Void)?
    var onEffectChosen: ((LogoEffect) -> Void)?
    var onMorsePlay: ((String) -> Void)?
    var onMorseStop: (() -> Void)?
    var onMorseLoopsChanged: ((Bool) -> Void)?
    var onMorseTextChanged: ((String) -> Void)?
    var onFinishChanged: ((MacFinish) -> Void)?
    var onLidChanged: ((MacLid) -> Void)?
    /// The brightness slider let go (or its drag was cancelled), so held-back state can go in.
    var onBrightnessDragEnded: (() -> Void)?

    private(set) var isDraggingBrightness = false

    init(finish: MacFinish, lid: MacLid = .sixteen) {
        self.finish = finish
        self.lid = lid
        // Nothing is known until the first update, which always applies: an empty panel is drawn once.
        let status = LogoStatus(isSupported: false, setting: nil, source: .daemon, isLit: false, outputLevel: 0)
        let state = PanelState(status: status, canControlDirectly: false, effect: .none, brightness: 1)
        self.state = state
        isOn = state.isOn
        followsBattery = state.followsBattery
        followsDisplayBrightness = state.followsDisplayBrightness
        breathesWhileCharging = state.breathesWhileCharging
        lightsWithLidClosed = state.lightsWithLidClosed
        launchesAtLogin = state.launchesAtLogin
        effect = state.effect
        loops = state.morseLoops
        brightness = state.brightness
    }

    func apply(_ state: PanelState) {
        self.state = state
        isOn = state.isOn
        followsBattery = state.followsBattery
        followsDisplayBrightness = state.followsDisplayBrightness
        breathesWhileCharging = state.breathesWhileCharging
        lightsWithLidClosed = state.lightsWithLidClosed
        launchesAtLogin = state.launchesAtLogin
        effect = state.effect
        loops = state.morseLoops
        if !isDraggingBrightness { brightness = state.brightness }
        // Nothing being sent: the highlight goes back with it, even if the report was missed (e.g. the
        // message ended while the panel was closed).
        if state.morse == nil { morseCharacter = nil }
    }

    // MARK: - What the controls do

    var isSendingMorse: Bool { state.isSendingMorse }

    /// Play can start a message when there's something to send, and always stop one.
    var canPlay: Bool {
        state.canAdjust && (MorseCode.canSend(morseText) || isSendingMorse)
    }

    func flipLogo(_ on: Bool) {
        isOn = on
        onLogoSwitched?(on)
    }

    func setBrightness(_ value: Double) {
        brightness = min(max(value, 0), 1)
        onBrightnessChanged?(brightness)
    }

    func dragBrightness(_ editing: Bool) {
        isDraggingBrightness = editing
        if !editing { onBrightnessDragEnded?() }
    }

    func flipDisplayBrightness(_ on: Bool) {
        followsDisplayBrightness = on
        // One thing at a time drives the brightness: the battery's switch goes off with it.
        if on { followsBattery = false }
        onFollowsDisplayBrightnessChanged?(on)
    }

    func flipBattery(_ on: Bool) {
        followsBattery = on
        if on { followsDisplayBrightness = false }
        onFollowsBatteryChanged?(on)
    }

    /// Not flipped here as the logo's switch is: starting at login can fail (a login item that won't be
    /// added), and the panel is told what actually happened as the state comes back round.
    func flipLaunchAtLogin(_ on: Bool) {
        onLaunchAtLoginChanged?(on)
    }

    func flipLightsWithLidClosed(_ on: Bool) {
        lightsWithLidClosed = on
        onLightsWithLidClosedChanged?(on)
    }

    func flipCharging(_ on: Bool) {
        breathesWhileCharging = on
        onBreathesWhileChargingChanged?(on)
    }

    /// The tab picked: one effect plays at a time, and None stops them all.
    func choose(_ effect: LogoEffect) {
        self.effect = effect
        onEffectChosen?(effect)
    }

    func setLoops(_ loops: Bool) {
        self.loops = loops
        onMorseLoopsChanged?(loops)
    }

    func play() {
        guard canPlay else { return }
        if isSendingMorse {
            onMorseStop?()
        } else {
            onMorsePlay?(morseText)
        }
    }

    /// Puts back the message typed last time, without telling the app it changed.
    func setMorseText(_ text: String) {
        morseText = String(text.prefix(MorseCode.maxLength))
    }

    func setFinish(_ finish: MacFinish) {
        guard finish != self.finish else { return }
        self.finish = finish
        onFinishChanged?(finish)
    }

    func setLid(_ lid: MacLid) {
        guard lid != self.lid else { return }
        self.lid = lid
        onLidChanged?(lid)
    }

    func editMorse(_ text: String) {
        setMorseText(text)
        onMorseTextChanged?(morseText)
    }

    /// What the field's tooltip says: the dots and dashes the message will be sent as.
    var morseNotation: String {
        let notation = MorseCode.notation(morseText)
        return notation.isEmpty ? "Letters, digits and punctuation" : notation
    }

    /// The code the group being sent stands out in. The highlight only follows the message the field
    /// still holds: editing mid-send shows the new message, unlit, until it's played.
    var highlightedNotation: AttributedString {
        var out = AttributedString()
        let words = MorseCode.words(morseText)
        let current = isSendingMorse && state.morse?.text == morseText ? morseCharacter : nil
        func add(_ text: String, _ group: Int?) {
            var part = AttributedString(text)
            part.foregroundColor = group != nil && group == current ? Color.accentColor : Color.secondary
            out.append(part)
        }
        guard !words.isEmpty else {
            add(morseNotation, nil) // the hint, while nothing has been typed
            return out
        }
        var index = 0
        for (w, word) in words.enumerated() {
            if w > 0 { add(" / ", nil) }
            for (c, code) in word.enumerated() {
                if c > 0 { add(" ", nil) }
                add(Self.dots(code), index)
                index += 1
            }
        }
        return out
    }

    /// The dots of a code raised to middle dots, which read as dots at that size where a full stop on
    /// the baseline would not.
    static func dots(_ code: String) -> String {
        code.replacingOccurrences(of: ".", with: "\u{B7}")
    }
}

/// The panel itself: the same groups of rows, in the order the menu shows them.
private struct PanelContent: View {
    let model: PanelModel
    let preview: LogoPreview

    private var state: PanelState { model.state }
    private var greyed: Double { PanelMetrics.greyedAlpha }
    private var greying: Animation { .easeInOut(duration: PanelMetrics.greying) }

    var body: some View {
        VStack(spacing: PanelMetrics.spacing) {
            PanelCard {
                PanelRow(title: "Mac Logo Control", icon: .init(symbol: "lightbulb.fill"),
                         isDimmed: !state.isSupported) {
                    Toggle("Apple logo backlight", isOn: Binding(get: { model.isOn }, set: { model.flipLogo($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .allowsHitTesting(state.canSwitch)
                }
            }

            if state.isSupported {
                PanelCard {
                    VStack(spacing: 10) {
                        // As wide as the card, its sides the card's own padding away, and tall as its
                        // shape makes it: no room left over either side.
                        LogoPreviewView(preview: preview, finish: model.finish, lid: model.lid)
                            .frame(width: LogoPreview.width, height: LogoPreview.height)
                        // Silver and space black, then 14 and 16 inch, as the MacBook Pro comes: the ones
                        // this Mac is, unless the user would rather see the others. In the tabs' bar.
                        HStack(spacing: PanelMetrics.labelSpacing + 2) {
                            OptionTabs(options: [
                                OptionTabs<MacFinish>.Option(value: .silver, title: "Silver"),
                                OptionTabs<MacFinish>.Option(value: .spaceBlack, title: "Space Black"),
                            ], selection: model.finish, choose: { model.setFinish($0) }, spreads: false,
                               surface: .card)
                            OptionTabs(options: MacLid.allCases.map {
                                OptionTabs<MacLid>.Option(value: $0, title: $0.title)
                            }, selection: model.lid, choose: { model.setLid($0) }, spreads: false,
                               surface: .card)
                        }
                    }
                    .padding(.vertical, 9)
                }
            }

            if state.showsAdjustments {
                brightnessCard
                VStack(spacing: PanelMetrics.headerToCard) {
                    GroupHeader("Effects")
                    effectsCard
                }
                .padding(.top, PanelMetrics.headerSpacing)
                VStack(spacing: PanelMetrics.headerToCard) {
                    GroupHeader("Morse Code")
                    morseCard
                }
                .padding(.top, PanelMetrics.headerSpacing)
            }

            // The app's own settings, which hold whatever the logo is doing: on a Mac without the
            // illuminated logo there's nothing to launch the app for, and they're left out.
            if state.isSupported {
                VStack(spacing: PanelMetrics.headerToCard) {
                    GroupHeader("General")
                PanelCard {
                    if state.showsLidClosedOption {
                        PanelRow(title: "Lid Closed", icon: .init(symbol: "laptopcomputer"),
                                 isGreyed: !state.canAdjust,
                                 help: "Keep the logo lit when you close the lid, on power or with an "
                                     + "external display. On power, your Mac stays awake with the lid closed. "
                                     + "The keyboard stays dark.") {
                            Toggle("Lit with lid closed", isOn: Binding(get: { model.lightsWithLidClosed },
                                                                       set: { model.flipLightsWithLidClosed($0) }))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }

                        RowSeparator()
                    }

                        PanelRow(title: "Launch at Login", icon: .init(symbol: "power"),
                                 help: "Start Mac Logo Control with your Mac, so the logo comes on by itself after a restart.") {
                            Toggle("Launch at Login", isOn: Binding(get: { model.launchesAtLogin },
                                                                    set: { model.flipLaunchAtLogin($0) }))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }
                }
                .padding(.top, PanelMetrics.headerSpacing)
            }

            if let message = state.message {
                // Wrapped at the panel's least width rather than stretched out on one line: it's the only
                // thing there, and a wide panel for one sentence reads oddly.
                Text(message)
                    .font(.system(size: NSFont.smallSystemFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: state.isSupported
                           ? .infinity
                           : PanelMetrics.minWidth - 2 * PanelMetrics.inset - 2 * PanelMetrics.textIndent,
                           alignment: .leading)
                    .padding(.horizontal, PanelMetrics.textIndent)
            }
        }
        .padding(.top, PanelMetrics.topInset)
        .padding(.bottom, PanelMetrics.inset)
        .padding(.horizontal, PanelMetrics.inset)
        .frame(minWidth: state.isSupported ? PanelMetrics.widthWithLiveView : PanelMetrics.minWidth,
               alignment: .top)


    }

    // MARK: - The brightness, the battery and the charging light

    private var brightnessCard: some View {
        PanelCard {
            PanelRow(title: "Automatic", icon: .init(symbol: "sun.max"), isGreyed: !state.canAdjust,
                     help: "The logo follows the display's brightness, which macOS keeps in step with the light around you.") {
                Toggle("Automatic brightness",
                       isOn: Binding(get: { model.followsDisplayBrightness },
                                     set: { model.flipDisplayBrightness($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            RowSeparator()

            HStack(spacing: PanelMetrics.labelSpacing) {
                Image(systemName: "sun.min.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: PanelMetrics.iconWidth)
                    .opacity(state.canChangeBrightness ? 1 : greyed)
                Slider(value: Binding(get: { model.brightness }, set: { model.setBrightness($0) }),
                       in: 0...1, onEditingChanged: { model.dragBrightness($0) })
                    .labelsHidden()
                    .accessibilityLabel("Brightness")
                    .allowsHitTesting(state.canChangeBrightness)
                    // It still shows the charge while the battery sets the brightness: faded, so it's
                    // plain it can't be moved, and the track keeps its colour on a light card.
                    .opacity(state.canChangeBrightness ? 1 : 0.5)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .opacity(state.canChangeBrightness ? 1 : greyed)
            }
            .padding(.leading, PanelMetrics.iconInset)
            .padding(.trailing, PanelMetrics.inset + 4)
            .frame(height: PanelMetrics.rowHeight)
            .animation(greying, value: state.canChangeBrightness)

            RowSeparator()

            PanelRow(title: "Battery", icon: .init(symbol: "battery.75percent"),
                     isGreyed: !state.canAdjust,
                     help: "The logo shows the battery's charge: normal brightness when it's full, dimmer as it runs down.") {
                Toggle("Brightness follows battery",
                       isOn: Binding(get: { model.followsBattery }, set: { model.flipBattery($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            RowSeparator()

            PanelRow(title: "Charging", icon: .init(symbol: "bolt.fill"),
                     isGreyed: !state.canAdjust,
                     help: "While the battery charges, the logo breathes like the old MacBook sleep light, then goes back to your effect.") {
                Toggle("Breathe while charging",
                       isOn: Binding(get: { model.breathesWhileCharging }, set: { model.flipCharging($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - The effects

    /// The effects, as tabs across one row: at most one plays at a time, and None stops them.
    private var effectsCard: some View {
        // No card around the tabs: they're one row, and a card behind them was just another layer under
        // the lozenge. The card's inset keeps them in line with the rows above and below.
        OptionTabs(options: effects.map { effect in
            OptionTabs<LogoEffect>.Option(value: effect, title: effect.title, symbol: Self.symbol(effect),
                                          help: effect == .sound
                                              ? "The logo glows with the sound your Mac is playing: brighter as "
                                                  + "it gets louder, peaking at your brightness. macOS asks once "
                                                  + "to let Mac Logo Control hear it." : nil)
        }, selection: model.effect, choose: { model.choose($0) })
            .allowsHitTesting(state.canAdjust)
            .opacity(state.canAdjust ? 1 : 0.7)
            // The panel already insets it as it does the cards: no padding of its own.
            .frame(height: PanelMetrics.rowHeight)
    }

    private var effects: [LogoEffect] {
        LogoEffect.allCases.filter { $0 != .sound || state.showsSound }
    }

    /// Each effect's symbol, beside its title in the tabs.
    private static func symbol(_ effect: LogoEffect) -> String {
        switch effect {
        case .none: "slash.circle"
        case .breathe: "wind"
        case .pulse: "waveform"
        case .heartbeat: "heart.fill"
        case .sound: "music.note"
        }
    }

    // MARK: - Morse code

    private var morseCard: some View {
        PanelCard {
            VStack(spacing: 6) {
                TextField("Message", text: Binding(get: { model.morseText }, set: { model.editMorse($0) }))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .onSubmit { model.play() }
                    .accessibilityLabel("Morse code message")

                // The code the message becomes, shown as it's typed, with the play button at its end;
                // while it's sending, the group going out now is lit.
                HStack(spacing: PanelMetrics.labelSpacing + 2) {
                    Text(model.highlightedNotation)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .accessibilityLabel("Morse code: \(model.morseNotation)")

                    Spacer(minLength: PanelMetrics.labelSpacing)

                    Button {
                        model.play()
                    } label: {
                        Image(systemName: model.isSendingMorse ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canPlay)
                    .help(model.isSendingMorse ? "Stop" : "Play")
                    .accessibilityLabel("Play Morse code")
                }
            }
            .padding(.horizontal, PanelMetrics.iconInset)
            .padding(.vertical, 7)
            .disabled(!state.canAdjust)
            // A disabled field only greys a little of itself: faded, as the rows around it are, it reads
            // as out of reach at a glance.
            .opacity(state.canAdjust ? 1 : 0.55)
            .animation(greying, value: state.canAdjust)

            RowSeparator()

            // The loop, on a row of its own, as a switch like the panel's other settings.
            PanelRow(title: "Repeat", icon: .init(symbol: "repeat"),
                     isGreyed: !state.canAdjust,
                     help: "Play the message over and over until it's stopped.") {
                Toggle("Repeat until stopped", isOn: Binding(get: { model.loops }, set: { model.setLoops($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Repeat Morse code")
            }
        }
    }
}

/// A rounded group of rows on glass, as System Settings has them.
private struct PanelCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .background(GlassMaterial(shape: RoundedRectangle(cornerRadius: PanelMetrics.cardRadius,
                                                              style: .continuous)))
    }
}

/// A row: its icon, its label, and its control at the trailing edge.
private struct PanelRow<Control: View>: View {
    let title: String
    let icon: PanelSymbol
    var isDimmed = false
    /// Whether it's out of reach for now (the logo is off): faded, and its control takes no clicks.
    var isGreyed = false
    var help: String?
    @ViewBuilder var control: Control

    var body: some View {
        // The label takes what the icon and the control leave, which is where the AppKit rows had it.
        // A greyed-out row fades its icon and label, and disables its control: fading the control too
        // would leave a switch's knob without its track.
        HStack(spacing: 0) {
            icon.opacity(isGreyed ? PanelMetrics.greyedAlpha : (isDimmed ? 0.35 : 1))
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundStyle(isDimmed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .opacity(isGreyed ? PanelMetrics.greyedAlpha : 1)
                .padding(.leading, PanelMetrics.iconInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Not `.disabled`: SwiftUI fades a disabled switch's track until it's gone on a light card.
            // A little fade of our own keeps its shape while saying it's out of reach.
            control
                .allowsHitTesting(!isGreyed)
                .opacity(isGreyed ? 0.7 : 1)
                .padding(.leading, PanelMetrics.labelSpacing)
        }
        .padding(.leading, PanelMetrics.iconInset)
        .padding(.trailing, PanelMetrics.controlInset)
        .frame(height: PanelMetrics.rowHeight)
        .animation(.easeInOut(duration: PanelMetrics.greying), value: isGreyed)
        .tip(help)
    }
}

/// A row of tabs, one per effect: the one playing is on a raised pill. Drawn here rather than with a
/// segmented `Picker`, which shows a segment's title or its icon but not both.
/// A row of tabs, for a choice of a few: the one picked sits on a lozenge of its own, which slides from
/// where it was to where it's going, in a bar of the cards' material.
private struct OptionTabs<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        /// The symbol beside the title, where there is one.
        var symbol: String?
        var help: String?
    }

    /// What the bar is drawn on: the panel itself, or a card, which is white in the light and lighter than
    /// the panel in the dark — the bar takes the opposite direction on each, so it shows on both.
    enum Surface { case panel, card }

    let options: [Option]
    let selection: Value
    let choose: (Value) -> Void
    /// Whether the bar fills the width it's given, the tabs spread across it, or hugs its tabs.
    var spreads = true
    var surface = Surface.panel

    @Environment(\.colorScheme) private var colorScheme
    /// One lozenge, shared by whichever tab is picked, so it slides rather than each lighting up on its own.
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
                let isSelected = option.value == selection
                Button {
                    choose(option.value)
                } label: {
                    HStack(spacing: 5) {
                        if let symbol = option.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 11, weight: .medium))
                        }
                        Text(option.title)
                            .font(.system(size: 13))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, 10)
                    // Each tab as wide as its icon and title need; the spacers share out the rest.
                    .frame(minWidth: 40, minHeight: 24)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: PanelMetrics.tabRadius, style: .continuous)
                                .fill(isDark ? Color.white.opacity(0.2) : Color.white)
                                .shadow(color: .black.opacity(isDark ? 0.3 : 0.15), radius: 2.5, y: 1)
                                .matchedGeometryEffect(id: "selection", in: pill)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .tip(option.help)
                if spreads, index < options.count - 1 { Spacer(minLength: 0) }
            }
        }
        // As wide as the cards, so its edges line up with theirs, with the tabs spread across it.
        .frame(maxWidth: spreads ? .infinity : nil)
        .padding(PanelMetrics.tabInset)
        // One background, and one only: the bar the tabs sit in, with the cards' corners. It takes the
        // opposite tone to what it sits on — white on the panel in the light, a shade of black on a card
        // that's white — so it shows in both appearances without a second surface.
        .background {
            let shape = RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
            shape
                .fill(barFill)
                .overlay { shape.strokeBorder(barRim, lineWidth: 1) }
        }
        // The lozenge slides, as a glass bar's does: quick, with a little bounce, stretching on the way
        // when the tabs it crosses are of different widths.
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: selection)
    }

    private var isDark: Bool { colorScheme == .dark }

    private var barFill: Color {
        switch (isDark, surface) {
        case (true, .panel): Color.white.opacity(0.07)
        case (true, .card): Color.white.opacity(0.10)
        case (false, .panel): Color.white.opacity(0.92)
        case (false, .card): Color.black.opacity(0.055)
        }
    }

    private var barRim: Color {
        isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.05)
    }
}

/// A row's icon: the system's symbol for it, in the label's own secondary colour.
private struct PanelSymbol: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.secondary)
            .frame(width: PanelMetrics.iconWidth, height: PanelMetrics.iconWidth)
    }
}

/// A group's title, outside its card, as System Settings writes them.
private struct GroupHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PanelMetrics.textIndent)
    }
}

/// The hairline between rows: from the text column to the trailing inset, as in System Settings.
private struct RowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .padding(.leading, PanelMetrics.textColumn)
            .padding(.trailing, PanelMetrics.controlInset)
    }
}

/// The lit, translucent material macOS 26 and later draw their settings' groups on: a soft gradient, and a
/// hairline rim that's lit at the top and fades toward the bottom, as light falls on an edge.
private struct GlassMaterial<S: InsettableShape>: View {
    /// The shape it's drawn in: a card's rounded rectangle, or the capsule the tabs sit in.
    var shape: S

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        let fill = isDark
            ? [Color.white.opacity(0.155), Color.white.opacity(0.075)]
            : [Color.white.opacity(0.92), Color.white.opacity(0.7)]
        let rim = isDark
            ? [Color.white.opacity(0.26), Color.white.opacity(0.04)]
            : [Color.black.opacity(0.10), Color.black.opacity(0.02)]
        shape
            .fill(LinearGradient(colors: fill, startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(LinearGradient(colors: rim, startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

/// Shows the panel's live view, which is AppKit's: it draws the lid with the logo's light on it.
private struct LogoPreviewView: NSViewRepresentable {
    let preview: LogoPreview
    let finish: MacFinish
    let lid: MacLid

    func makeNSView(context: Context) -> LogoPreview { preview }
    func updateNSView(_ view: LogoPreview, context: Context) {
        view.setFinish(finish)
        view.setLid(lid)
    }
}

private extension View {
    /// A tooltip, where there is one to give.
    @ViewBuilder func tip(_ text: String?) -> some View {
        if let text {
            self.help(text)
        } else {
            self
        }
    }
}

/// A live view of the logo: the back of the MacBook Pro in its own finish (space black or silver) and
/// in the lid's real proportions, with the logo glowing on it.
private final class LogoPreview: NSView {
    /// How the panel draws the live view: as wide as a card's inside and always as tall as the
    /// 16-inch lid — switching to the 14-inch scales the lid down inside the frame, not the frame
    /// itself, so the panel never shifts when the size tab changes.
    static let width: CGFloat = PanelMetrics.liveViewWidth
    static var height: CGFloat { (width / geometry(for: .sixteen).aspect).rounded() }

    /// One lid's shape, off the same Apple shots the lid is drawn from. The 14-inch is a shade
    /// squarer, and a physically smaller machine.
    private struct LidGeometry {
        let aspect: CGFloat
        /// The whole lid's size next to the 16-inch's, off Apple's dimensions (31.26 cm across,
        /// against its 35.57) — the 14-inch is drawn this much smaller inside the same frame.
        let scale: CGFloat
    }
    private static func geometry(for lid: MacLid) -> LidGeometry {
        switch lid {
        case .fourteen: LidGeometry(aspect: 1.436, scale: 0.879)
        case .sixteen: LidGeometry(aspect: 1.456, scale: 1)
        }
    }
    /// The lid is Apple's own shot of it, knocked out of its plate (see `scripts/make-lid-images.py`)
    /// — anodised aluminium, machined edges and the unlit mark, all exactly as Apple photographs it.
    /// The logo's light is the only thing drawn over it.
    private let lid = CALayer()
    /// The logo's light, faded in by the glow, lined up with the mark printed in the shot.
    private let logo = CALayer()
    /// How tall the lid was last drawn at, which finish, and which lid's shape, so all are only
    /// set when they change.
    private var drawnHeight: CGFloat = 0
    private var drawnFinish: MacFinish?
    private var drawnLid: MacLid
    private var laidOutLid: MacLid?

    init(finish: MacFinish, lid lidSize: MacLid = .sixteen) {
        drawnLid = lidSize
        super.init(frame: .zero)
        wantsLayer = true
        lid.contentsGravity = .resize
        layer?.addSublayer(lid)
        lid.addSublayer(logo)
        logo.contentsGravity = .resize
        setFinish(finish)
        show(glow: 0)

        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Live view of the Apple logo")
    }

    /// Shows the other lid: its shot and its shape. The frame keeps the 16-inch lid's size whatever
    /// the lid, so this asks for a layout as well — `layout()` notices the shape changed even
    /// though nothing resized.
    func setLid(_ lid: MacLid) {
        guard lid != drawnLid else { return }
        drawnLid = lid
        repaintLid()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let frameHeight = bounds.height
        guard frameHeight > 0, frameHeight != drawnHeight || laidOutLid != drawnLid else { return }
        drawnHeight = frameHeight
        laidOutLid = drawnLid
        let g = Self.geometry(for: drawnLid)
        // The frame is always the 16-inch lid's: the 16-inch fills it, the 14-inch — the physically
        // smaller machine — is drawn scaled down and centred in it. All the shares below are of the
        // lid's own height, not the frame's.
        let size = NSSize(width: (bounds.width * g.scale).rounded(),
                          height: (bounds.width * g.scale / g.aspect).rounded())
        withoutAnimation {
            let lidFrame = NSRect(x: (bounds.width - size.width) / 2,
                                  y: (frameHeight - size.height) / 2,
                                  width: size.width, height: size.height)
            lid.frame = lidFrame
            // The light is the printed mark's own shape, cut from the same shot and kept on the
            // shot's own canvas — so it rides the lid frame exactly, logo centred where the
            // photograph put it, at any size the lid is drawn at. No bloom: the shot carries
            // its own light, and the mark alone is what comes on.
            logo.frame = CGRect(origin: .zero, size: lidFrame.size)
        }
    }

    /// Shows the lid in `finish` — another shot, nothing else about the live view changes.
    func setFinish(_ finish: MacFinish) {
        guard finish != drawnFinish else { return }
        drawnFinish = finish
        repaintLid()
    }

    /// Puts the current lid and finish's shot on the layer, with its mark — the light's shape —
    /// over it. Before the finish is known there's nothing to show, and `setFinish` paints it
    /// once it is.
    private func repaintLid() {
        guard let finish = drawnFinish else { return }
        withoutAnimation {
            lid.contents = Self.shot(size: drawnLid, finish: finish, mark: false)
            logo.contents = Self.shot(size: drawnLid, finish: finish, mark: true)
        }
    }

    /// The lid shots and the logo's shapes, each loaded the first time it's asked for and kept:
    /// every menu shows one pair, and the tabs move between them.
    private static var shots: [String: NSImage] = [:]

    /// The lid's shot, or the shape of the logo printed on it (`mark`) — the same canvas each time,
    /// which is what lines the light up with the print.
    private static func shot(size: MacLid, finish: MacFinish, mark: Bool) -> NSImage? {
        let name = "lid-\(size == .fourteen ? "14" : "16")inch-\(finish == .silver ? "silver" : "spaceblack")"
            + (mark ? "-mark" : "")
        if let shot = shots[name] { return shot }
        guard let url = shotURL(named: name), let shot = NSImage(contentsOf: url) else { return nil }
        shots[name] = shot
        return shot
    }

    /// A shot from the app's `Lids` folder, or, for a debug binary run out of `.build` (the picture
    /// renderer, the tests), from the checkout it was built in.
    private static func shotURL(named name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Lids") { return url }
        var dir = Bundle.main.bundleURL
        for _ in 0..<5 {
            dir = dir.deletingLastPathComponent()
            let url = dir.appendingPathComponent("Resources/Lids/\(name).png")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    /// The glow last drawn.
    private var shownGlow: Double?

    /// Called on every frame while the menu is open. A change too small to see isn't drawn, so a
    /// steady logo costs nothing. The shot underneath keeps its printed mark: the light rising
    /// over it is what reads as the logo coming on.
    func show(glow: Double) {
        if let shownGlow, abs(glow - shownGlow) < 0.002 { return }
        shownGlow = glow
        withoutAnimation {
            logo.opacity = Float(glow)
        }
    }

    private func withoutAnimation(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}

#if DEBUG
/// Draws the panel in each state to a PNG, for checking how it looks.
///
/// Optional settings, for pictures of the app (e.g. the website's). Without them the output is as before:
/// - `MACLOGOCONTROL_RENDER_SCALE`: pixels per point, 2 by default, up to 16 (e.g. 4 for a larger, crisp picture,
///   or 14 for a live view about 800 points wide on a Retina screen). With a scale given, layer images and
///   shadows are drawn as a screen at that scale draws them, so the logo stays sharp. (Without one, they are
///   drawn at the screen's scale, as before.)
/// - `MACLOGOCONTROL_RENDER_TRANSPARENT`: leaves the background clear instead of a menu-like grey, so the
///   picture can be placed on any backdrop (the cards are translucent, as in the real menu).
/// - `MACLOGOCONTROL_RENDER_GLOW`, `MACLOGOCONTROL_RENDER_BRIGHTNESS`, `MACLOGOCONTROL_RENDER_EFFECT`: the live view's
///   glow (0.75), the slider (0.6, also the charge in `battery-*.png`) and the effect that's on
///   (`heartbeat`) in the panels.
/// - `MACLOGOCONTROL_RENDER_GLOWS`: glow levels, e.g. `0,0.5,1`, to also draw the live view alone at each
///   level, in both finishes (`live-black-50.png`, `live-silver-50.png`). It also prints where the lid is
///   in each panel, to place those pictures over it.
/// - `MACLOGOCONTROL_RENDER_LIGHT`: also draws the logo's light alone, fully lit, lid-sized on clear
///   (`live-light.png`). Over `live-black-0.png` at opacity g it gives the live view at glow g, as `show(glow:)`
///   draws it: the light is the mark alone, with no bloom. It is the same in both finishes.
/// - `MACLOGOCONTROL_RENDER_ICON`: also draws the menu bar icon while the logo is on (`icon-on.png`, black
///   on clear, as the template the menu bar tints).
/// - `MACLOGOCONTROL_RENDER_MENU`: also draws the whole menu with the logo on (`menu-dark.png`, `menu-light.png`):
///   the panel and, under it, the menu's own items (Disable Password and Launch at Login checked, Lit with Lid
///   Closed with its second line, Quit Mac Logo Control), in the menu's rounded shape on clear. An `NSMenu` can't be
///   drawn offscreen, so the items are drawn here to look like its (`MenuPicture`).
@MainActor
enum PanelRenderer {
    private struct Options {
        var scale = 2
        /// Without a scale given, the window draws at the screen's, as it always has.
        var scaleIsSet = false
        var transparent = false
        var glow = 0.75
        var brightness = 0.6
        var effect = LogoEffect.heartbeat
        var glows: [Double] = []
        var light = false
        var icon = false
        var menu = false

        init(_ environment: [String: String]) {
            if let scale = environment["MACLOGOCONTROL_RENDER_SCALE"].flatMap(Int.init), (1...16).contains(scale) {
                self.scale = scale
                scaleIsSet = true
            }
            transparent = environment["MACLOGOCONTROL_RENDER_TRANSPARENT"] != nil
            if let glow = environment["MACLOGOCONTROL_RENDER_GLOW"].flatMap(Double.init) { self.glow = min(max(glow, 0), 1) }
            if let brightness = environment["MACLOGOCONTROL_RENDER_BRIGHTNESS"].flatMap(Double.init) {
                self.brightness = min(max(brightness, 0), 1)
            }
            if let effect = environment["MACLOGOCONTROL_RENDER_EFFECT"].flatMap(LogoEffect.init(rawValue:)) { self.effect = effect }
            glows = (environment["MACLOGOCONTROL_RENDER_GLOWS"] ?? "").split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.map { min(max($0, 0), 1) }
            light = environment["MACLOGOCONTROL_RENDER_LIGHT"] != nil
            icon = environment["MACLOGOCONTROL_RENDER_ICON"] != nil
            menu = environment["MACLOGOCONTROL_RENDER_MENU"] != nil
        }
    }

    /// Drawing assumes top-down layers, as in the panel.
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    /// A window that draws its views at any scale, not just the screen's, so text and symbols stay sharp.
    private final class RenderWindow: NSWindow {
        var scale: CGFloat?
        override var backingScaleFactor: CGFloat { scale ?? super.backingScaleFactor }
        /// The switches and the slider take their colours from the key window's, so without this they'd
        /// be drawn grey, as they are in a menu before it becomes key.
        override var canBecomeKey: Bool { true }
    }

    static func render(to folder: String) {
        let options = Options(ProcessInfo.processInfo.environment)
        func state(_ setting: LogoIllumination, isSupported: Bool = true, canControlDirectly: Bool = true,
                   canFollowSound: Bool = true, followsBattery: Bool = false, followsDisplayBrightness: Bool = false,
                   breathesWhileCharging: Bool = false) -> PanelState {
            let status = LogoStatus(isSupported: isSupported, setting: isSupported ? setting : nil, source: .daemon,
                                    isLit: setting == .on, outputLevel: 0.2)
            return PanelState(status: status, canControlDirectly: canControlDirectly, canFollowSound: canFollowSound,
                              effect: options.effect, brightness: options.brightness, followsBattery: followsBattery,
                              followsDisplayBrightness: followsDisplayBrightness,
                              breathesWhileCharging: breathesWhileCharging)
        }
        let on = state(.on)
        var looping = on
        looping.morse = MorseMessage(text: "SOS", loops: true)
        looping.morseLoops = true
        let states = [("on", on), ("morse", looping), ("off", state(.off)), ("battery", state(.on, followsBattery: true)),
                      ("automatic", state(.on, followsDisplayBrightness: true)),
                      ("nosound", state(.on, canFollowSound: false)),
                      ("charging", state(.on, breathesWhileCharging: true)),
                      ("fallback", state(.on, canControlDirectly: false)), ("unsupported", state(.off, isSupported: false))]
        for (name, state) in states {
            for (suffix, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                picture { write(state, appearance: appearance, options: options, to: "\(folder)/\(name)-\(suffix).png") }
            }
        }
        for (suffix, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            picture { write(on, finish: .silver, appearance: appearance, options: options,
                            to: "\(folder)/on-silver-\(suffix).png") }
        }
        if options.menu {
            for (name, lid) in [("menu", MacLid.sixteen), ("menu-14", MacLid.fourteen)] {
                for (suffix, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                    picture {
                        let panel = ControlPanel(finish: .spaceBlack, lid: lid)
                        panel.setMorseText("SOS")
                        panel.update(on)
                        panel.showGlow(options.glow)
                        panel.settle()
                        draw(MenuPicture(panel: panel, isDark: appearance == .darkAqua), appearance: appearance,
                             options: options, background: nil, to: "\(folder)/\(name)-\(suffix).png")
                    }
                }
            }
        }
        for glow in options.glows {
            for (name, finish) in [("black", MacFinish.spaceBlack), ("silver", .silver)] {
                picture {
                    let preview = LogoPreview(finish: finish)
                    preview.frame = NSRect(origin: .zero, size: LogoPreview.renderedLidSize)
                    preview.show(glow: glow)
                    draw(preview, options: options, background: nil,
                         to: "\(folder)/live-\(name)-\(Int((glow * 100).rounded())).png")
                }
            }
        }
        if options.light {
            picture {
                let preview = LogoPreview(finish: .spaceBlack)
                preview.frame = NSRect(origin: .zero, size: LogoPreview.renderedLidSize)
                preview.showLightAlone()
                draw(preview, options: options, background: nil, to: "\(folder)/live-light.png")
            }
        }
        if options.icon, let symbol = NSImage(systemSymbolName: MenuBarIcon.symbolName, accessibilityDescription: nil) {
            // The status item's button draws its template image at its own size, in the menu bar's text colour.
            picture {
                let icon = NSImageView(image: symbol)
                icon.contentTintColor = .black
                icon.frame = NSRect(origin: .zero, size: symbol.size)
                let container = FlippedView(frame: icon.frame)
                container.addSubview(icon)
                draw(container, options: options, background: nil, to: "\(folder)/icon-on.png")
            }
        }
    }

    /// Draws one picture and lets go of it before the next is drawn.
    ///
    /// The renderer runs a plain loop rather than a run loop, so nothing drains AppKit's autorelease pool
    /// while it goes: every `NSBitmapImageRep` and its data stayed alive until the process ended. At the
    /// media script's scale 6 that was tens of gigabytes by the 70th of the 101 glow levels, and the system
    /// killed the process. Nothing else drains the pool here, because the app never returns to a run loop
    /// between pictures.
    private static func picture(_ draw: () -> Void) {
        autoreleasepool(invoking: draw)
    }

    private static func write(_ state: PanelState, finish: MacFinish = .spaceBlack, appearance: NSAppearance.Name,
                              options: Options, to path: String) {
        let panel = ControlPanel(finish: finish)
        panel.setMorseText("SOS")
        panel.update(state)
        panel.showGlow(state.isOn ? options.glow : 0)
        panel.settle()
        let background = appearance == .darkAqua ? NSColor(white: 0.2, alpha: 1) : NSColor(white: 0.9, alpha: 1)
        draw(panel, appearance: appearance, options: options, background: options.transparent ? nil : background,
             to: path)
    }

    /// Draws `view` into a PNG at the options' scale, on `background`, or on clear without one.
    private static func draw(_ view: NSView, appearance: NSAppearance.Name = .darkAqua, options: Options,
                             background: NSColor?, to path: String) {
        let window = RenderWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        if options.scaleIsSet { window.scale = CGFloat(options.scale) }
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = background ?? .clear
        window.isOpaque = background != nil
        window.contentView = view
        window.setContentSize(view.frame.size)
        // Invisible, but ordered in and key, as a menu is while it's open: the switches and the slider
        // take their colours from a key window, and would be drawn grey otherwise. (They also need the
        // app itself to be active, which `AppDelegate` sees to before the first picture is drawn.)
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
        window.makeKey()
        // AppKit's controls draw in the accent colour only in a key window, so wait for it to be one.
        let deadline = Date().addingTimeInterval(0.3)
        while !window.isKeyWindow, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        // And without a text selection or a focus ring in the picture.
        window.makeFirstResponder(nil)
        window.displayIfNeeded()
        if view is ControlPanel || view is MenuPicture {
            reportTruncatedLabels(in: view, path: path)
            if !options.glows.isEmpty { reportLid(in: view, path: path) }
        }

        guard let layer = view.layer ?? window.contentView?.layer else { return }
        let scale = options.scale
        if options.scaleIsSet { drawAsScreen(layer, scale: CGFloat(scale)) }
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
                                         pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return }
        let cg = context.cgContext
        if let background {
            cg.setFillColor(background.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
        } else {
            cg.clear(CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
        }
        // The view's layers are top-down, the bitmap's context bottom-up.
        cg.translateBy(x: 0, y: CGFloat(rep.pixelsHigh))
        cg.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        layer.render(in: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        window.orderOut(nil)
    }

    /// `render(in:)` draws an image set as a layer's contents (the live view's logo) as it would for the screen, and
    /// shadows in the bitmap's pixels whatever its scale. A screen at `scale` draws images at that scale and shadows
    /// in points, so this sets each layer up to match.
    private static func drawAsScreen(_ layer: CALayer, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        func prepare(_ layer: CALayer) {
            layer.contentsScale = scale
            if let image = layer.contents as? NSImage {
                // Made into a bitmap at this scale; left as it is, it would be one made for the screen.
                layer.contents = image.layerContents(forContentsScale: scale)
            }
            layer.shadowRadius *= scale
            layer.shadowOffset = CGSize(width: layer.shadowOffset.width * scale, height: layer.shadowOffset.height * scale)
            layer.sublayers?.forEach(prepare)
        }
        prepare(layer)
        CATransaction.commit()
    }

    /// Prints the live view's lid frame in the picture (the panel, or the whole menu), in points, and the
    /// picture's size.
    private static func reportLid(in picture: NSView, path: String) {
        func previews(in view: NSView) -> [LogoPreview] {
            view.subviews.flatMap { ($0 as? LogoPreview).map { [$0] } ?? previews(in: $0) }
        }
        guard let preview = previews(in: picture).first, !preview.isHiddenOrHasHiddenAncestor else { return }
        let lid = picture.convert(preview.renderedLidFrame, from: preview)
        print("\(path): lid at x \(lid.minX), y \(lid.minY), \(lid.width) × \(lid.height) in a panel "
              + "\(picture.bounds.width) × \(picture.bounds.height) pt")
    }

    /// The menu as it opens below the menu bar icon: the panel, then the menu's own items laid out as `NSMenu`
    /// lays them out (5 points above and below, items 22 high or 34 with a second line, the text 24 in and a
    /// check at 9, separators 11 high with their line 10 in), in the menu's rounded shape, on clear. Drawn here
    /// because an `NSMenu` can't be drawn offscreen.
    private final class MenuPicture: NSView {
        override var isFlipped: Bool { true }
        private static let padding: CGFloat = 5
        private static let cornerRadius: CGFloat = 12
        private let isDark: Bool

        init(panel: ControlPanel, isDark: Bool) {
            self.isDark = isDark
            super.init(frame: NSRect(x: 0, y: 0, width: panel.bounds.width, height: panel.bounds.height))
            wantsLayer = true
            panel.setFrameOrigin(NSPoint(x: 0, y: Self.padding))
            addSubview(panel)
            var y = panel.frame.maxY
            y = addSeparator(at: y)
            y = addItem("Disable Password", checked: true, at: y)
            y = addSeparator(at: y)
            y = addItem("Quit Mac Logo Control", at: y)
            setFrameSize(NSSize(width: panel.bounds.width, height: y + Self.padding))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        private func addSeparator(at y: CGFloat) -> CGFloat {
            let line = NSBox(frame: NSRect(x: 10, y: y + 5, width: bounds.width - 20, height: 1))
            line.boxType = .separator
            addSubview(line)
            return y + 11
        }

        private func addItem(_ title: String, subtitle: String? = nil, checked: Bool = false, at y: CGFloat) -> CGFloat {
            let height: CGFloat = subtitle == nil ? 22 : 34
            let label = NSTextField(labelWithString: title)
            label.font = .menuFont(ofSize: 13)
            label.textColor = .labelColor
            label.sizeToFit()
            if let subtitle {
                let second = NSTextField(labelWithString: subtitle)
                second.font = .menuFont(ofSize: 11)
                second.textColor = .secondaryLabelColor
                second.sizeToFit()
                let both = label.frame.height + second.frame.height - 1
                label.setFrameOrigin(NSPoint(x: 24, y: y + (height - both) / 2))
                second.setFrameOrigin(NSPoint(x: 24, y: label.frame.maxY - 1))
                addSubview(second)
            } else {
                label.setFrameOrigin(NSPoint(x: 24, y: y + (height - label.frame.height) / 2))
            }
            addSubview(label)
            if checked, let symbol = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .bold)) {
                let check = NSImageView(image: symbol)
                check.contentTintColor = .labelColor
                check.sizeToFit()
                check.setFrameOrigin(NSPoint(x: 9 + (11 - check.frame.width) / 2, y: y + (height - check.frame.height) / 2))
                addSubview(check)
            }
            return y + height
        }

        override func draw(_ dirtyRect: NSRect) {
            let fill = isDark ? NSColor(srgbRed: 40 / 255, green: 40 / 255, blue: 43 / 255, alpha: 1)
                : NSColor(srgbRed: 242 / 255, green: 242 / 255, blue: 245 / 255, alpha: 1)
            let edge = isDark ? NSColor(white: 1, alpha: 0.16) : NSColor(white: 0, alpha: 0.14)
            fill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()
            let inner = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25),
                                     xRadius: Self.cornerRadius - 0.25, yRadius: Self.cornerRadius - 0.25)
            inner.lineWidth = 0.5
            edge.setStroke()
            inner.stroke()
        }
    }

    /// Says which of the panel's labels its column can't hold, so a narrower panel can be checked. SwiftUI
    /// truncates one without saying so, so the text is measured here rather than read back from a label.
    private static func reportTruncatedLabels(in view: NSView, path: String) {
        func panel(in view: NSView) -> ControlPanel? {
            if let panel = view as? ControlPanel { return panel }
            for subview in view.subviews { if let found = panel(in: subview) { return found } }
            return nil
        }
        guard let panel = panel(in: view) else { return }
        // From the text column to the switch: the row's padding, its icon, its label's gap, the switch is
        // 36 wide, and its own gap's worth of room at least. The panel is as wide as its content, so this
        // is measured from what it came out as.
        let room = panel.bounds.width - 2 * PanelMetrics.inset - PanelMetrics.textColumn
            - PanelMetrics.controlInset - 36 - PanelMetrics.labelSpacing
        for label in panel.rowLabels {
            let width = (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
            if width > room + 0.5 {
                print("\(path): \"\(label)\" is truncated (\(room) of \(width) pt wide)")
            }
        }
    }
}

private extension LogoPreview {
    /// The live view's size without the panel around it: just the lid, as the panel draws it.
    static var renderedLidSize: NSSize { NSSize(width: width, height: height) }

    /// Where the lid is drawn in the view (centred, as `layout()` places it).
    var renderedLidFrame: NSRect {
        let g = Self.geometry(for: drawnLid)
        let size = NSSize(width: (bounds.width * g.scale).rounded(),
                          height: (bounds.width * g.scale / g.aspect).rounded())
        return NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// Leaves only the logo's light, fully lit: no lid at all.
    func showLightAlone() {
        lid.contents = nil
        logo.opacity = 1
    }
}
#endif

