import AppKit
import LogoLightCore
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

    /// The panel is as wide and as tall as its content wants (the effect tabs across one row are what make
    /// it wide); this is the least it takes, so a panel without them still fits the menu's own items.
    static let width = PanelMetrics.minWidth

    private let model: PanelModel
    private let preview: LogoPreview
    private let host: NSHostingView<PanelContent>

    /// `finish` is the colour of this Mac's case, which the live view copies.
    init(finish: MacFinish = .spaceBlack) {
        let preview = LogoPreview(finish: finish)
        let model = PanelModel(finish: finish)
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
        model.onEffectChosen = { [weak self] in self?.onEffectChosen?($0) }
        model.onMorsePlay = { [weak self] in self?.onMorsePlay?($0) }
        model.onMorseStop = { [weak self] in self?.onMorseStop?() }
        model.onMorseLoopsChanged = { [weak self] in self?.onMorseLoopsChanged?($0) }
        model.onMorseTextChanged = { [weak self] in self?.onMorseTextChanged?($0) }
        model.onFinishChanged = { [weak self] in self?.onPreviewFinishChanged?($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Top-down, as the menu's own items beside it are drawn, and as the picture of it is.
    override var isFlipped: Bool { true }

    /// Shows how brightly the logo is glowing right now, from 0 to 1.
    func showGlow(_ glow: Double) {
        preview.show(glow: glow)
    }

    func update(_ state: PanelState) {
        guard state != model.state else { return }
        model.apply(state)
        // SwiftUI lays the new rows out on its next turn, and the menu item is as tall as the panel, so
        // it's sized once they're in.
        DispatchQueue.main.async { [weak self] in self?.sizeToFitContent() }
    }

    /// Puts back the message typed last time.
    func setMorseText(_ text: String) {
        model.setMorseText(text)
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
        guard state.showsAdjustments else { return ["LogoLight"] }
        return ["LogoLight", "Battery", "Charging"]
            + LogoEffect.allCases.filter { $0 != .none && ($0 != .sound || state.showsSound) }.map(\.title)
    }
}

/// The numbers the panel is laid out with, the same as System Settings' where they can be.
private enum PanelMetrics {
    /// The least width the panel takes: enough for the menu's own items, and for the rows when the
    /// effects are hidden. It's as wide as its content wants, otherwise.
    static let minWidth: CGFloat = 172
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
    /// The corners of the cards: rounder than before, as macOS 26 and later draw them.
    static let cardRadius: CGFloat = 13
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
    var effect: LogoEffect
    var loops: Bool
    /// The brightness the slider shows; not the app's while it's being dragged.
    var brightness: Double
    /// The message typed, which is the panel's while it's being edited.
    var morseText = "SOS"
    /// The finish the live view is painted in: this Mac's, unless the user picked the other.
    var finish: MacFinish

    var onLogoSwitched: ((Bool) -> Void)?
    var onBrightnessChanged: ((Double) -> Void)?
    var onFollowsBatteryChanged: ((Bool) -> Void)?
    var onFollowsDisplayBrightnessChanged: ((Bool) -> Void)?
    var onBreathesWhileChargingChanged: ((Bool) -> Void)?
    var onLightsWithLidClosedChanged: ((Bool) -> Void)?
    var onEffectChosen: ((LogoEffect) -> Void)?
    var onMorsePlay: ((String) -> Void)?
    var onMorseStop: (() -> Void)?
    var onMorseLoopsChanged: ((Bool) -> Void)?
    var onMorseTextChanged: ((String) -> Void)?
    var onFinishChanged: ((MacFinish) -> Void)?

    private var isDraggingBrightness = false

    init(finish: MacFinish) {
        self.finish = finish
        // Nothing is known until the first update, which always applies: an empty panel is drawn once.
        let status = LogoStatus(isSupported: false, setting: nil, source: .daemon, isLit: false, outputLevel: 0)
        let state = PanelState(status: status, canControlDirectly: false, effect: .none, brightness: 1)
        self.state = state
        isOn = state.isOn
        followsBattery = state.followsBattery
        followsDisplayBrightness = state.followsDisplayBrightness
        breathesWhileCharging = state.breathesWhileCharging
        lightsWithLidClosed = state.lightsWithLidClosed
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
        effect = state.effect
        loops = state.morseLoops
        if !isDraggingBrightness { brightness = state.brightness }
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

    func editMorse(_ text: String) {
        setMorseText(text)
        onMorseTextChanged?(morseText)
    }

    /// What the field's tooltip says: the dots and dashes the message will be sent as.
    var morseNotation: String {
        let notation = MorseCode.notation(morseText)
        return notation.isEmpty ? "Letters, digits and punctuation" : notation
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
                PanelRow(title: "LogoLight", icon: .init(symbol: "lightbulb.fill"),
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
                        LogoPreviewView(preview: preview, finish: model.finish)
                            .frame(height: LogoPreview.height)
                            .frame(maxWidth: .infinity)
                        // Silver and space black, as the MacBook Pro comes: the one this Mac is, unless the
                        // user would rather see the other.
                        Picker("Preview finish", selection: Binding(get: { model.finish },
                                                                    set: { model.setFinish($0) })) {
                            Text("Silver").tag(MacFinish.silver)
                            Text("Space Black").tag(MacFinish.spaceBlack)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 200)
                        .accessibilityLabel("Preview finish")
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

            if let message = state.message {
                // Wrapped at the panel's least width rather than stretched out on one line: it's the only
                // thing there, and a wide panel for one sentence reads oddly.
                Text(message)
                    .font(.system(size: NSFont.smallSystemFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: PanelMetrics.minWidth - 2 * PanelMetrics.inset - 2 * PanelMetrics.textIndent,
                           alignment: .leading)
                    .padding(.horizontal, PanelMetrics.textIndent)
            }
        }
        .padding(.top, PanelMetrics.topInset)
        .padding(.bottom, PanelMetrics.inset)
        .padding(.horizontal, PanelMetrics.inset)
        .frame(minWidth: PanelMetrics.minWidth, alignment: .top)
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

            if state.showsLidClosedOption {
                RowSeparator()

                PanelRow(title: "Lid Closed", icon: .init(symbol: "laptopcomputer"),
                         isGreyed: !state.canAdjust,
                         help: "Keep the logo lit when you close the lid, on power or with an external display. "
                             + "On power, your Mac stays awake with the lid closed. The keyboard stays dark.") {
                    Toggle("Lit with lid closed",
                           isOn: Binding(get: { model.lightsWithLidClosed }, set: { model.flipLightsWithLidClosed($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - The effects

    /// The effects, as tabs across one row: at most one plays at a time, and None stops them.
    private var effectsCard: some View {
        PanelCard {
            EffectTabs(effects: effects, selection: model.effect, choose: { model.choose($0) })
                .allowsHitTesting(state.canAdjust)
                .opacity(state.canAdjust ? 1 : 0.7)
                .padding(.horizontal, PanelMetrics.iconInset)
                .frame(height: PanelMetrics.rowHeight)
        }
    }

    private var effects: [LogoEffect] {
        LogoEffect.allCases.filter { $0 != .sound || state.showsSound }
    }

    // MARK: - Morse code

    private var morseCard: some View {
        PanelCard {
            HStack(spacing: PanelMetrics.labelSpacing + 2) {
                TextField("Message", text: Binding(get: { model.morseText }, set: { model.editMorse($0) }))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .onSubmit { model.play() }
                    .accessibilityLabel("Morse code message")
                    .help(model.morseNotation)

                Button {
                    model.play()
                } label: {
                    Image(systemName: model.isSendingMorse ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!model.canPlay)
                .help(model.isSendingMorse ? "Stop" : "Play")
                .accessibilityLabel("Play Morse code")

                Toggle(isOn: Binding(get: { model.loops }, set: { model.setLoops($0) })) {
                    Image(systemName: "repeat")
                }
                .toggleStyle(.button)
                .help("Repeat until stopped")
                .accessibilityLabel("Repeat Morse code")
            }
            .padding(.horizontal, PanelMetrics.iconInset)
            .frame(height: PanelMetrics.rowHeight)
            .disabled(!state.canAdjust)
        }
    }
}

/// A rounded group of rows on glass, as System Settings has them.
private struct PanelCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .background(GlassMaterial())
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
private struct EffectTabs: View {
    let effects: [LogoEffect]
    let selection: LogoEffect
    let choose: (LogoEffect) -> Void

    @Environment(\.colorScheme) private var colorScheme
    /// One pill, shared by whichever tab is picked: it slides from the old to the new rather than each
    /// tab lighting up on its own, which is how macOS 26's glass tabs move the selection.
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(effects, id: \.self) { effect in
                let isSelected = effect == selection
                Button {
                    choose(effect)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: Self.symbol(effect))
                            .font(.system(size: 11, weight: .medium))
                        Text(effect.title)
                            .font(.system(size: 13))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, 10)
                    // Each tab as wide as its icon and title need, as AppKit sizes a segment's.
                    .frame(minWidth: 40, minHeight: 22)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isDark ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(.white))
                                .overlay {
                                    if !isDark {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(.black.opacity(0.10), lineWidth: 0.5)
                                    }
                                }
                                .shadow(color: .black.opacity(isDark ? 0.18 : 0.10), radius: 1.5, y: 0.5)
                                .matchedGeometryEffect(id: "selection", in: pill)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(effect.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .tip(effect == .sound ? "The logo glows with the sound your Mac is playing: brighter as it "
                      + "gets louder, peaking at your brightness. macOS asks once to let LogoLight hear it." : nil)
            }
        }
        // No track behind the tabs: the card is the backing, and the one that plays is the raised pill.
        .padding(.vertical, 2)
        // A glass tab's pill slides: a spring that settles quickly, with a little overshoot, and it
        // stretches on the way when the tabs are of different widths.
        .animation(.spring(response: 0.32, dampingFraction: 0.74), value: selection)
    }

    private var isDark: Bool { colorScheme == .dark }

    /// Each effect's symbol: what the tabs had as rows before they were tabs.
    private static func symbol(_ effect: LogoEffect) -> String {
        switch effect {
        case .none: "slash.circle"
        case .breathe: "wind"
        case .pulse: "waveform"
        case .heartbeat: "heart.fill"
        case .sound: "music.note"
        }
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
private struct GlassMaterial: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
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

    func makeNSView(context: Context) -> LogoPreview { preview }
    func updateNSView(_ view: LogoPreview, context: Context) { view.setFinish(finish) }
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
    /// The 14-inch MacBook Pro's lid is 31.3 × 22.1 cm, and the live view is drawn to that shape at
    /// whatever height it's given.
    static let aspectRatio: CGFloat = 31.3 / 22.1
    /// How tall the panel draws the live view.
    static let height: CGFloat = 200
    /// Its width at that height.
    static var width: CGFloat { (height * aspectRatio).rounded() }

    private let lid = CAGradientLayer()
    /// The logo as it looks unlit: polished metal in the lid, catching the light along a diagonal.
    private let mark = CAGradientLayer()
    /// The mark's shape, which the gradient above shows through.
    private let markShape = CALayer()
    /// Its light, faded in by the glow.
    private let logo = CALayer()
    /// How tall the lid was last drawn at, and in which finish, so both are only set when they change.
    private var drawnHeight: CGFloat = 0
    private var drawnFinish: MacFinish?

    init(finish: MacFinish) {
        super.init(frame: .zero)
        wantsLayer = true
        lid.cornerCurve = .continuous
        layer?.addSublayer(lid)
        markShape.contentsGravity = .resizeAspect
        mark.mask = markShape
        mark.startPoint = CGPoint(x: 0.1, y: 0)
        mark.endPoint = CGPoint(x: 0.9, y: 1)
        for layer in [mark, logo] as [CALayer] {
            layer.contentsGravity = .resizeAspect
            lid.addSublayer(layer)
        }
        logo.shadowColor = NSColor.white.cgColor
        logo.shadowOffset = .zero
        setFinish(finish)
        show(glow: 0)

        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Live view of the Apple logo")
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        guard height > 0, height != drawnHeight else { return }
        drawnHeight = height
        let size = NSSize(width: (height * Self.aspectRatio).rounded(), height: height)
        withoutAnimation {
            lid.frame = NSRect(x: (bounds.width - size.width) / 2, y: 0, width: size.width, height: size.height)
            lid.cornerRadius = height * 0.085
            lid.borderWidth = height * 0.006
            logo.shadowRadius = height * 0.085
            let logoSize = (height * 0.317).rounded()
            let logoFrame = NSRect(x: (size.width - logoSize) / 2, y: (size.height - logoSize) / 2,
                                   width: logoSize, height: logoSize)
            mark.frame = logoFrame
            markShape.frame = mark.bounds
            logo.frame = logoFrame
            // The mark and the light are images made at the logo's size: at another height they're remade.
            logo.contents = Self.logoImage(.white, size: logoSize)
            markShape.contents = Self.logoShape(size: logoSize)
            if let finish = drawnFinish { Self.paintMark(mark, finish: finish) }
        }
    }

    /// Paints the lid in `finish`, keeping the logo's light as it is: anodised aluminium, with a faint
    /// sheen toward the top, a fine machined edge, and the unlit mark in the metal.
    func setFinish(_ finish: MacFinish) {
        guard finish != drawnFinish else { return }
        drawnFinish = finish
        let (top, bottom, edge, markOpacity): (NSColor, NSColor, NSColor, Float) = switch finish {
        case .spaceBlack:
            (NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1),
             NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1),
             NSColor(white: 1, alpha: 0.14), 0.9)
        case .silver:
            (NSColor(srgbRed: 0.86, green: 0.865, blue: 0.87, alpha: 1),
             NSColor(srgbRed: 0.72, green: 0.725, blue: 0.735, alpha: 1),
             NSColor(white: 0, alpha: 0.16), 0.9)
        }
        withoutAnimation {
            lid.colors = [top.cgColor, bottom.cgColor]
            lid.borderColor = edge.cgColor
            Self.paintMark(mark, finish: finish)
            markBaseOpacity = markOpacity
            // A logo that's already lit keeps it that way: the metal shows only as far as it's dark.
            mark.opacity = markOpacity * Float(1 - (shownGlow ?? 0))
        }
    }

    /// Paints the unlit mark: the metal it's cut from, with a sheen across it, as a polished logo looks
    /// in the lid when the light behind it is off.
    private static func paintMark(_ mark: CAGradientLayer, finish: MacFinish) {
        let (lit, shaded, sheen): (NSColor, NSColor, NSColor) = switch finish {
        case .spaceBlack:
            (NSColor(white: 0.26, alpha: 1), NSColor(white: 0.07, alpha: 1), NSColor(white: 0.42, alpha: 1))
        case .silver:
            (NSColor(white: 0.66, alpha: 1), NSColor(white: 0.44, alpha: 1), NSColor(white: 0.95, alpha: 1))
        }
        mark.colors = [lit.cgColor, sheen.cgColor, shaded.cgColor, sheen.cgColor, lit.cgColor]
        mark.locations = [0, 0.22, 0.5, 0.78, 1]
    }

    /// The mark's shape alone (its alpha), for the gradient to show through.
    private static func logoShape(size: CGFloat) -> NSImage? {
        let symbol = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: nil)
        return symbol?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: max(size, 1), weight: .regular))
    }

    /// The Apple logo in `color`, at the size it sits on the lid.
    private static func logoImage(_ color: NSColor, size: CGFloat) -> NSImage? {
        let symbol = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: nil)
        return symbol?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: max(size, 1), weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    /// The glow last drawn, and how solid the unlit mark is before the light fades it out.
    private var shownGlow: Double?
    private var markBaseOpacity: Float = 0.9

    /// Called on every frame while the menu is open. A change too small to see isn't drawn, so a
    /// steady logo costs nothing.
    func show(glow: Double) {
        if let shownGlow, abs(glow - shownGlow) < 0.002 { return }
        shownGlow = glow
        withoutAnimation {
            logo.opacity = Float(glow)
            logo.shadowOpacity = Float(glow)
            // Lit, what's seen is the light, not the polished metal behind it: the mark fades out with it,
            // so a logo at half brightness still reads as lit rather than as dark metal with a sheen.
            mark.opacity = markBaseOpacity * Float(1 - glow)
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
/// - `LOGOLIGHT_RENDER_SCALE`: pixels per point, 2 by default, up to 16 (e.g. 4 for a larger, crisp picture,
///   or 14 for a live view about 800 points wide on a Retina screen). With a scale given, layer images and
///   shadows are drawn as a screen at that scale draws them: the logo sharp, and its glow as wide as in the
///   menu. (Without one, the logo is drawn at the screen's scale and its glow in pixels, as before.)
/// - `LOGOLIGHT_RENDER_TRANSPARENT`: leaves the background clear instead of a menu-like grey, so the
///   picture can be placed on any backdrop (the cards are translucent, as in the real menu).
/// - `LOGOLIGHT_RENDER_GLOW`, `LOGOLIGHT_RENDER_BRIGHTNESS`, `LOGOLIGHT_RENDER_EFFECT`: the live view's
///   glow (0.75), the slider (0.6, also the charge in `battery-*.png`) and the effect that's on
///   (`heartbeat`) in the panels.
/// - `LOGOLIGHT_RENDER_GLOWS`: glow levels, e.g. `0,0.5,1`, to also draw the live view alone at each
///   level, in both finishes (`live-black-50.png`, `live-silver-50.png`). It also prints where the lid is
///   in each panel, to place those pictures over it.
/// - `LOGOLIGHT_RENDER_LIGHT`: also draws the logo's light alone, fully lit, lid-sized on clear: with its glow
///   (`live-light.png`) and without it (`live-light-shape.png`). Over `live-black-0.png`, the first at opacity g
///   with the second on top, both in a group at opacity g, give the live view at glow g, as `show(glow:)` draws
///   it (the glow's own opacity is g as well, so it shows at g²). The light is the same in both finishes.
/// - `LOGOLIGHT_RENDER_ICON`: also draws the menu bar icon while the logo is on (`icon-on.png`, black
///   on clear, as the template the menu bar tints).
/// - `LOGOLIGHT_RENDER_MENU`: also draws the whole menu with the logo on (`menu-dark.png`, `menu-light.png`):
///   the panel and, under it, the menu's own items (Disable Password and Launch at Login checked, Lit with Lid
///   Closed with its second line, Quit LogoLight), in the menu's rounded shape on clear. An `NSMenu` can't be
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
            if let scale = environment["LOGOLIGHT_RENDER_SCALE"].flatMap(Int.init), (1...16).contains(scale) {
                self.scale = scale
                scaleIsSet = true
            }
            transparent = environment["LOGOLIGHT_RENDER_TRANSPARENT"] != nil
            if let glow = environment["LOGOLIGHT_RENDER_GLOW"].flatMap(Double.init) { self.glow = min(max(glow, 0), 1) }
            if let brightness = environment["LOGOLIGHT_RENDER_BRIGHTNESS"].flatMap(Double.init) {
                self.brightness = min(max(brightness, 0), 1)
            }
            if let effect = environment["LOGOLIGHT_RENDER_EFFECT"].flatMap(LogoEffect.init(rawValue:)) { self.effect = effect }
            glows = (environment["LOGOLIGHT_RENDER_GLOWS"] ?? "").split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.map { min(max($0, 0), 1) }
            light = environment["LOGOLIGHT_RENDER_LIGHT"] != nil
            icon = environment["LOGOLIGHT_RENDER_ICON"] != nil
            menu = environment["LOGOLIGHT_RENDER_MENU"] != nil
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
                write(state, appearance: appearance, options: options, to: "\(folder)/\(name)-\(suffix).png")
            }
        }
        for (suffix, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            write(on, finish: .silver, appearance: appearance, options: options, to: "\(folder)/on-silver-\(suffix).png")
        }
        if options.menu {
            for (suffix, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                let panel = ControlPanel(finish: .spaceBlack)
                panel.setMorseText("SOS")
                panel.update(on)
                panel.showGlow(options.glow)
                panel.settle()
                draw(MenuPicture(panel: panel, isDark: appearance == .darkAqua), appearance: appearance, options: options,
                     background: nil, to: "\(folder)/menu-\(suffix).png")
            }
        }
        for glow in options.glows {
            for (name, finish) in [("black", MacFinish.spaceBlack), ("silver", .silver)] {
                let preview = LogoPreview(finish: finish)
                preview.frame = NSRect(origin: .zero, size: LogoPreview.renderedLidSize)
                preview.show(glow: glow)
                draw(preview, options: options, background: nil,
                     to: "\(folder)/live-\(name)-\(Int((glow * 100).rounded())).png")
            }
        }
        if options.light {
            for (name, withGlow) in [("live-light", true), ("live-light-shape", false)] {
                let preview = LogoPreview(finish: .spaceBlack)
                preview.frame = NSRect(origin: .zero, size: LogoPreview.renderedLidSize)
                preview.showLightAlone(withGlow: withGlow)
                draw(preview, options: options, background: nil, to: "\(folder)/\(name).png")
            }
        }
        if options.icon, let symbol = NSImage(systemSymbolName: MenuBarIcon.symbolName, accessibilityDescription: nil) {
            // The status item's button draws its template image at its own size, in the menu bar's text colour.
            let icon = NSImageView(image: symbol)
            icon.contentTintColor = .black
            icon.frame = NSRect(origin: .zero, size: symbol.size)
            let container = FlippedView(frame: icon.frame)
            container.addSubview(icon)
            draw(container, options: options, background: nil, to: "\(folder)/icon-on.png")
        }
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
            y = addItem("Launch at Login", checked: true, at: y)
            y = addSeparator(at: y)
            y = addItem("Quit LogoLight", at: y)
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

    /// Where the lid is drawn in the view (centred at the top, as `layout()` places it).
    var renderedLidFrame: NSRect {
        let size = NSSize(width: (bounds.height * Self.aspectRatio).rounded(), height: bounds.height)
        return NSRect(x: (bounds.width - size.width) / 2, y: 0, width: size.width, height: size.height)
    }

    /// Leaves only the logo's light, fully lit, with or without its glow: no lid and no unlit mark.
    func showLightAlone(withGlow: Bool) {
        lid.colors = nil
        lid.borderWidth = 0
        mark.isHidden = true
        logo.opacity = 1
        logo.shadowOpacity = withGlow ? 1 : 0
    }
}
#endif

