import AppKit
import LogoLightCore
import SwiftUI

/// The panel at the top of the menu, in the style of System Settings on macOS 27: groups of rows on glass,
/// a switch for the logo first, where it's easiest to reach, then a live view of it, a brightness slider
/// with the Battery and Charging switches under it, then a switch for each effect. Everything below the
/// live view is greyed out while the logo is off, and the slider is while the battery sets the brightness.
@MainActor
final class ControlPanel: NSView {
    var onLogoSwitched: ((Bool) -> Void)?
    var onBrightnessChanged: ((Double) -> Void)?
    var onFollowsBatteryChanged: ((Bool) -> Void)?
    var onBreathesWhileChargingChanged: ((Bool) -> Void)?
    var onEffectChosen: ((LogoEffect) -> Void)?
    /// Play pressed (or Return in the field), with the message typed.
    var onMorsePlay: ((String) -> Void)?
    /// Play pressed while it shows stop: a message is being sent.
    var onMorseStop: (() -> Void)?
    /// The loop switch flipped: on, a message repeats until it's stopped.
    var onMorseLoopsChanged: ((Bool) -> Void)?
    /// The message edited (to remember it for next time).
    var onMorseTextChanged: ((String) -> Void)?

    /// As narrow as the menu's own items allow (they need 153 with Disable Password, and the menu is as
    /// wide as its widest item). The longest label, "Heartbeat" (61 pt at 13 pt, 64 with Bold Text),
    /// still fits between its tile and its switch, which leave it 72.
    private static let width: CGFloat = 172
    /// Around the panel's contents (9 at the top), and between its sections.
    private static let inset: CGFloat = 6
    private static let topInset: CGFloat = 9
    private static let spacing: CGFloat = 6
    /// The width of the cards and of everything else in the panel.
    private static let cardWidth = width - 2 * inset
    /// How far text outside the cards is indented, on both sides.
    private static let textIndent: CGFloat = 12
    /// A row: as tall as a row in System Settings' lists, a little tighter for a menu.
    private static let rowHeight: CGFloat = 36
    /// Where row text starts inside a card.
    fileprivate static let textColumn: CGFloat = 40
    /// Where the icon tiles start inside a card, and their size.
    private static let tileInset: CGFloat = 8
    fileprivate static let tileSize: CGFloat = 24
    /// How far a switch sits from the card's edge (the same as the tiles), and the least room between
    /// it and its label. A hairline between rows stops this far short of the trailing edge too.
    fileprivate static let switchInset: CGFloat = 8
    private static let labelSpacing: CGFloat = 4
    /// The corners of the cards: rounder than before, as macOS 26 and later draw them.
    fileprivate static let cardRadius: CGFloat = 13
    /// Between one group and the next group's header, and between a header and its card.
    private static let headerSpacing: CGFloat = 8
    private static let headerToCardSpacing: CGFloat = 4
    /// How the brightness and the effects look while the logo is off.
    private static let greyedOutAlpha: CGFloat = 0.4
    /// How long they take to grey out or come back when the logo is switched.
    private static let greyingDuration = 0.22

    private let stack = NSStackView()
    private let preview: LogoPreview
    private lazy var previewWell = PreviewWell(content: preview)
    private let logoTile = IconTile(symbol: "lightbulb.fill", color: .systemOrange)
    private let logoLabel = NSTextField(labelWithString: "LogoLight")
    private let logoSwitch = SwitchToggle(isOn: false, label: "Apple logo backlight")
    private let brightnessCard = Card()
    private let brightnessRow = NSView()
    private let dimIcon = NSImageView()
    private let brightIcon = NSImageView()
    private let brightnessSlider = TrackingSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    /// Under the slider, in its card: the battery indicator, which has the brightness follow the charge.
    private let batteryTile = IconTile(symbol: "battery.75percent", color: .systemGreen)
    private let batteryLabel = NSTextField(labelWithString: "Battery")
    private let batterySwitch = SwitchToggle(isOn: false, label: "Brightness follows battery")
    private var batteryRow = NSView()
    /// Under it: the charging light, which has the logo breathe while the battery charges.
    private let chargingTile = IconTile(symbol: "bolt.fill", color: .systemYellow)
    private let chargingLabel = NSTextField(labelWithString: "Charging")
    private let chargingSwitch = SwitchToggle(isOn: false, label: "Breathe while charging")
    private var chargingRow = NSView()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let effectsHeader = NSTextField(labelWithString: "Effects")
    /// Each line of text outside the cards is in one of these, which indents it (and is what's hidden).
    private let messageContainer = NSStackView()
    private let effectsHeaderContainer = NSStackView()
    private let effectsCard = Card()
    private var effectRows: [(effect: LogoEffect, tile: IconTile, label: NSTextField, toggle: SwitchToggle)] = []
    /// The Sound effect's row and the hairline above it, hidden where the sound can't be heard.
    private var soundRows: [NSView] = []
    private let morseHeader = NSTextField(labelWithString: "Morse Code")
    private let morseHeaderContainer = NSStackView()
    private let morseCard = Card()
    private let morseRow = NSView()
    private let morseField = NSTextField()
    /// Play, which turns to stop while a message is sent, and the loop switch beside it.
    private let playButton = ControlPanel.symbolButton("play.fill")
    private let loopButton = ControlPanel.symbolButton("repeat")

    /// What the panel shows now. `nil` until the first update, which always applies.
    private var state: PanelState?

    /// `finish` is the colour of this Mac's case, which the live view copies.
    init(finish: MacFinish = .spaceBlack) {
        preview = LogoPreview(finish: finish)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 100))
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    /// Shows how brightly the logo is glowing right now, from 0 to 1.
    func showGlow(_ glow: Double) {
        preview.show(glow: glow)
    }

    func update(_ state: PanelState) {
        guard state != self.state else { return }
        let old = self.state
        self.state = state
        previewWell.isHidden = !state.isSupported
        let animated = window?.isVisible == true

        // The switch shows what was asked for, even while the logo is still fading. It only looks
        // disabled while a password is needed.
        set(logoSwitch, on: state.isOn, animated: animated)
        logoSwitch.isEnabled = state.canSwitch
        logoLabel.textColor = state.isSupported ? .labelColor : .tertiaryLabelColor
        logoTile.isDimmed = !state.isSupported

        brightnessCard.isHidden = !state.showsAdjustments
        effectsHeaderContainer.isHidden = !state.showsAdjustments
        effectsCard.isHidden = !state.showsAdjustments
        morseHeaderContainer.isHidden = !state.showsAdjustments
        morseCard.isHidden = !state.showsAdjustments

        if !brightnessSlider.isTracking { brightnessSlider.doubleValue = state.brightness }
        brightnessSlider.isEnabled = state.canChangeBrightness
        set(batterySwitch, on: state.followsBattery, animated: animated)
        batterySwitch.isEnabled = state.canAdjust
        set(chargingSwitch, on: state.breathesWhileCharging, animated: animated)
        chargingSwitch.isEnabled = state.canAdjust
        for row in effectRows {
            set(row.toggle, on: row.effect == state.effect, animated: animated)
            row.toggle.isEnabled = state.canAdjust
        }
        for view in soundRows { view.isHidden = !state.showsSound }
        morseField.isEnabled = state.canAdjust
        playButton.state = state.isSendingMorse ? .on : .off
        playButton.image = Self.symbol(state.isSendingMorse ? "stop.fill" : "play.fill", size: 11)
        playButton.toolTip = state.isSendingMorse ? "Stop" : "Play"
        loopButton.state = state.morseLoops ? .on : .off
        updateMorseButtons()
        greyOut([brightnessRow: !state.canChangeBrightness, batteryRow: !state.canAdjust,
                 chargingRow: !state.canAdjust, effectsCard.rows: !state.canAdjust,
                 morseCard.rows: !state.canAdjust], animated: animated)

        messageLabel.stringValue = state.message ?? ""
        messageContainer.isHidden = state.message == nil
        // Only these change the panel's height.
        if old?.isSupported != state.isSupported || old?.showsAdjustments != state.showsAdjustments
            || old?.showsSound != state.showsSound || old?.message != state.message {
            resizeToFit()
        }
    }

    /// Greys out the brightness, the Battery and Charging switches, the effects and Morse code, or brings them back, as one fade
    /// of their rows (the controls in them don't change their own look).
    private func greyOut(_ rows: [NSView: Bool], animated: Bool) {
        let changes = rows.map { (view: $0.key, alpha: $0.value ? Self.greyedOutAlpha : 1) }
            .filter { $0.view.alphaValue != $0.alpha }
        guard !changes.isEmpty else { return }
        guard animated else {
            for change in changes { change.view.alphaValue = change.alpha }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.greyingDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for change in changes { change.view.animator().alphaValue = change.alpha }
        }
    }

    /// Sets a switch to `on`, animating its knob when the panel is on screen.
    private func set(_ toggle: SwitchToggle, on: Bool, animated: Bool) {
        guard toggle.isOn != on else { return }
        toggle.set(on: on, animated: animated)
    }

    // MARK: - Layout

    private func build() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Self.spacing
        stack.edgeInsets = NSEdgeInsets(top: Self.topInset, left: Self.inset, bottom: Self.inset, right: Self.inset)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.widthAnchor.constraint(equalToConstant: Self.width),
        ])

        // The logo: on/off at the top, where the user wanted it (easier to reach than below the live
        // view), then the live view, then the brightness.
        logoSwitch.onChange = { [weak self] in self?.onLogoSwitched?($0) }
        let logoCard = Card()
        logoCard.add([row(tile: logoTile, label: logoLabel, toggle: logoSwitch)])
        addFullWidth(logoCard)

        addFullWidth(previewWell)

        dimIcon.image = Self.symbol("sun.min.fill", size: 11)
        brightIcon.image = Self.symbol("sun.max.fill", size: 15)
        for icon in [dimIcon, brightIcon] { icon.contentTintColor = .secondaryLabelColor }
        brightnessSlider.isContinuous = true
        brightnessSlider.target = self
        brightnessSlider.action = #selector(brightnessChanged)
        brightnessSlider.setAccessibilityLabel("Brightness")
        layOutBrightnessRow()
        batterySwitch.onChange = { [weak self] in self?.onFollowsBatteryChanged?($0) }
        batteryRow = row(tile: batteryTile, label: batteryLabel, toggle: batterySwitch)
        batteryRow.toolTip = "The logo shows the battery's charge: normal brightness when it's full, dimmer as it runs down."
        chargingSwitch.onChange = { [weak self] in self?.onBreathesWhileChargingChanged?($0) }
        chargingRow = row(tile: chargingTile, label: chargingLabel, toggle: chargingSwitch)
        chargingRow.toolTip = "While the battery charges, the logo breathes like the old MacBook sleep light, then goes back to your effect."
        brightnessCard.add([brightnessRow, Separator(), batteryRow, Separator(), chargingRow])
        addFullWidth(brightnessCard)

        // Only on a Mac without the logo, where nothing else is shown.
        messageLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 0 // as many as it needs: the panel resizes to fit
        messageLabel.preferredMaxLayoutWidth = Self.cardWidth - 2 * Self.textIndent
        addIndented(messageLabel, in: messageContainer)

        // Effects: one switch each; at most one is on. Sound (the logo follows the sound the Mac
        // plays) is last, and only where the sound can be heard.
        effectsHeader.font = .systemFont(ofSize: 13, weight: .semibold)
        effectsHeader.textColor = .labelColor
        addIndented(effectsHeader, in: effectsHeaderContainer, topSpacing: Self.headerSpacing)
        stack.setCustomSpacing(Self.headerToCardSpacing, after: effectsHeaderContainer)

        var rows: [NSView] = []
        for effect in LogoEffect.allCases where effect != .none {
            let tile = IconTile(symbol: Self.symbolName(for: effect), color: Self.color(for: effect))
            let label = NSTextField(labelWithString: effect.title)
            let toggle = SwitchToggle(isOn: false, label: effect.title)
            toggle.onChange = { [weak self] isOn in self?.choose(effect, isOn: isOn) }
            effectRows.append((effect, tile, label, toggle))
            if !rows.isEmpty { rows.append(Separator()) }
            let row = row(tile: tile, label: label, toggle: toggle)
            rows.append(row)
            if effect == .sound {
                row.toolTip = "The logo glows with the sound your Mac is playing: brighter as it gets louder, "
                    + "peaking at your brightness. macOS asks once to let LogoLight hear it."
                soundRows = [rows[rows.count - 2], row]
            }
        }
        effectsCard.add(rows)
        addFullWidth(effectsCard)

        // Morse code: type a message and press play, which turns to stop while it's sent. The loop
        // switch, as in a music player, makes it repeat until it's stopped.
        morseHeader.font = effectsHeader.font
        morseHeader.textColor = .secondaryLabelColor
        addIndented(morseHeader, in: morseHeaderContainer, topSpacing: Self.headerSpacing)
        stack.setCustomSpacing(Self.headerToCardSpacing, after: morseHeaderContainer)
        layOutMorseRow()
        morseCard.add([morseRow])
        addFullWidth(morseCard)
    }

    /// The message field, then play and loop, in one row as narrow as the effects'.
    private func layOutMorseRow() {
        morseField.placeholderString = "Message"
        morseField.font = .systemFont(ofSize: 12)
        morseField.bezelStyle = .roundedBezel
        morseField.lineBreakMode = .byTruncatingTail
        morseField.usesSingleLineMode = true
        morseField.cell?.isScrollable = true
        morseField.cell?.wraps = false
        morseField.delegate = self
        morseField.target = self
        morseField.action = #selector(morseFieldReturned) // Return plays it
        morseField.setAccessibilityLabel("Morse code message")

        playButton.toolTip = "Play"
        playButton.setAccessibilityLabel("Play Morse code")
        playButton.target = self
        playButton.action = #selector(playPressed)
        loopButton.toolTip = "Repeat until stopped"
        loopButton.setAccessibilityLabel("Repeat Morse code")
        loopButton.target = self
        loopButton.action = #selector(loopPressed)
        for view in [morseField, playButton, loopButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            morseRow.addSubview(view)
        }
        NSLayoutConstraint.activate([
            morseRow.heightAnchor.constraint(equalToConstant: Self.rowHeight),
            morseField.leadingAnchor.constraint(equalTo: morseRow.leadingAnchor, constant: Self.tileInset),
            morseField.centerYAnchor.constraint(equalTo: morseRow.centerYAnchor),
            morseField.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -Self.labelSpacing),
            playButton.centerYAnchor.constraint(equalTo: morseRow.centerYAnchor),
            playButton.trailingAnchor.constraint(equalTo: loopButton.leadingAnchor, constant: -Self.labelSpacing),
            loopButton.centerYAnchor.constraint(equalTo: morseRow.centerYAnchor),
            loopButton.trailingAnchor.constraint(equalTo: morseRow.trailingAnchor, constant: -Self.switchInset),
        ])
        updateMorseButtons()
    }

    /// Puts back the message typed last time.
    func setMorseText(_ text: String) {
        morseField.stringValue = String(text.prefix(MorseCode.maxLength))
        updateMorseButtons()
    }

    /// Play can start a message when there's something to send, and always stop one; the loop
    /// switch can always be flipped.
    private func updateMorseButtons() {
        let canAdjust = state?.canAdjust ?? false
        playButton.isEnabled = canAdjust && (MorseCode.canSend(morseField.stringValue) || playButton.state == .on)
        loopButton.isEnabled = canAdjust
        let notation = MorseCode.notation(morseField.stringValue)
        morseField.toolTip = notation.isEmpty ? "Letters, digits and punctuation" : notation
    }

    private func row(tile: IconTile, label: NSTextField, toggle: SwitchToggle) -> NSView {
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail

        let row = NSView()
        for view in [tile, label, toggle] {
            view.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(view)
        }
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: Self.rowHeight),
            tile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Self.tileInset),
            tile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Self.textColumn),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -Self.labelSpacing),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Self.switchInset),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func layOutBrightnessRow() {
        for view in [dimIcon, brightnessSlider, brightIcon] {
            view.translatesAutoresizingMaskIntoConstraints = false
            brightnessRow.addSubview(view)
        }
        NSLayoutConstraint.activate([
            brightnessRow.heightAnchor.constraint(equalToConstant: Self.rowHeight),
            // The small sun sits under the icon tiles, and the track starts at the text column.
            dimIcon.centerXAnchor.constraint(equalTo: brightnessRow.leadingAnchor, constant: Self.tileInset + Self.tileSize / 2),
            dimIcon.centerYAnchor.constraint(equalTo: brightnessRow.centerYAnchor),
            // AppKit's slider draws its track 8 in from its edge, so it lines up with the text.
            brightnessSlider.leadingAnchor.constraint(equalTo: brightnessRow.leadingAnchor,
                                                      constant: Self.textColumn - 8),
            brightnessSlider.centerYAnchor.constraint(equalTo: brightnessRow.centerYAnchor),
            brightnessSlider.trailingAnchor.constraint(equalTo: brightIcon.leadingAnchor, constant: -4),
            brightIcon.trailingAnchor.constraint(equalTo: brightnessRow.trailingAnchor, constant: -12),
            brightIcon.centerYAnchor.constraint(equalTo: brightnessRow.centerYAnchor),
        ])
    }

    private func addFullWidth(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalToConstant: Self.cardWidth).isActive = true
    }

    /// Adds text outside the cards, indented as in System Settings, with `topSpacing` above it.
    private func addIndented(_ text: NSView, in container: NSStackView, topSpacing: CGFloat = 0) {
        container.addArrangedSubview(text)
        container.edgeInsets = NSEdgeInsets(top: topSpacing, left: Self.textIndent, bottom: 0, right: Self.textIndent)
        addFullWidth(container)
    }

    private func resizeToFit() {
        layoutSubtreeIfNeeded()
        let height = stack.fittingSize.height
        if abs(frame.height - height) > 0.5 { setFrameSize(NSSize(width: Self.width, height: height)) }
    }

    // MARK: - Actions

    @objc private func brightnessChanged() {
        onBrightnessChanged?(brightnessSlider.doubleValue)
    }

    @objc private func playPressed() {
        if playButton.state == .on {
            onMorseStop?()
        } else {
            onMorsePlay?(morseField.stringValue)
        }
    }

    @objc private func loopPressed() {
        onMorseLoopsChanged?(loopButton.state == .on)
    }

    /// Return plays the message, unless one is being sent (stopping it takes the button).
    @objc private func morseFieldReturned() {
        guard playButton.isEnabled, playButton.state != .on else { return }
        onMorsePlay?(morseField.stringValue)
    }

    private func choose(_ effect: LogoEffect, isOn: Bool) {
        for other in effectRows where other.effect != effect { set(other.toggle, on: false, animated: true) }
        onEffectChosen?(isOn ? effect : .none)
    }

    // MARK: - Styling

    private static func symbolName(for effect: LogoEffect) -> String {
        switch effect {
        case .none: "lightbulb"
        case .breathe: "wind"
        case .pulse: "waveform"
        case .heartbeat: "heart.fill"
        case .sound: "music.note"
        }
    }

    private static func color(for effect: LogoEffect) -> NSColor {
        switch effect {
        case .none: .systemGray
        case .breathe: .systemTeal
        case .pulse: .systemIndigo
        case .heartbeat: .systemPink
        case .sound: .systemPurple
        }
    }

    /// A native icon button, bordered as a toolbar's are. It's a toggle, so it stays lit while its
    /// action is under way: Play while a message is sent, Repeat while it loops.
    private static func symbolButton(_ name: String) -> NSButton {
        let button = NSButton(image: symbol(name, size: 11) ?? NSImage(), target: nil, action: nil)
        button.bezelStyle = .texturedRounded
        button.setButtonType(.toggle)
        button.imagePosition = .imageOnly
        return button
    }

    fileprivate static func symbol(_ name: String, size: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium))
    }
}

extension ControlPanel: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        if morseField.stringValue.count > MorseCode.maxLength {
            morseField.stringValue = String(morseField.stringValue.prefix(MorseCode.maxLength))
        }
        updateMorseButtons()
        onMorseTextChanged?(morseField.stringValue)
    }
}

/// A live view of the logo: the back of the MacBook Pro in its own finish (space black or silver) and
/// in the lid's real proportions, with the logo glowing on it.
private final class LogoPreview: NSView {
    /// The 14-inch MacBook Pro's lid is 31.3 × 22.1 cm.
    private static let lidSize = NSSize(width: 116, height: 82)
    /// A little larger than on the real lid, so the glow reads at this size.
    private static let logoSize = NSSize(width: 26, height: 26)

    private let lid = CAGradientLayer()
    /// The logo as it looks unlit: a faint polished shape in the aluminium.
    private let mark = CALayer()
    /// Its light, faded in by the glow.
    private let logo = CALayer()

    init(finish: MacFinish) {
        super.init(frame: .zero)
        wantsLayer = true
        heightAnchor.constraint(equalToConstant: Self.lidSize.height).isActive = true

        // Anodised aluminium: a faint sheen toward the top, and a fine machined edge.
        let (top, bottom, edge, markColor, markOpacity): (NSColor, NSColor, NSColor, NSColor, Float) = switch finish {
        case .spaceBlack:
            (NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1), NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1),
             NSColor(white: 1, alpha: 0.14), .white, 0.08)
        case .silver:
            (NSColor(srgbRed: 0.86, green: 0.865, blue: 0.87, alpha: 1), NSColor(srgbRed: 0.72, green: 0.725, blue: 0.735, alpha: 1),
             NSColor(white: 0, alpha: 0.16), .black, 0.12)
        }
        lid.colors = [top.cgColor, bottom.cgColor]
        lid.cornerRadius = 7
        lid.cornerCurve = .continuous
        lid.borderWidth = 0.5
        lid.borderColor = edge.cgColor
        layer?.addSublayer(lid)

        let symbol = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: nil)
        func logoImage(_ color: NSColor) -> NSImage? {
            symbol?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: Self.logoSize.height, weight: .regular)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
        }
        for layer in [mark, logo] {
            layer.contentsGravity = .resizeAspect
            lid.addSublayer(layer)
        }
        mark.contents = logoImage(markColor)
        mark.opacity = markOpacity
        logo.contents = logoImage(.white)
        logo.shadowColor = NSColor.white.cgColor
        logo.shadowOffset = .zero
        logo.shadowRadius = 7
        show(glow: 0)

        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Live view of the Apple logo")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let lidSize = Self.lidSize, logoSize = Self.logoSize
        withoutAnimation {
            lid.frame = NSRect(x: (bounds.width - lidSize.width) / 2, y: 0, width: lidSize.width, height: lidSize.height)
            let logoFrame = NSRect(x: (lidSize.width - logoSize.width) / 2, y: (lidSize.height - logoSize.height) / 2,
                                   width: logoSize.width, height: logoSize.height)
            mark.frame = logoFrame
            logo.frame = logoFrame
        }
    }

    /// The glow last drawn.
    private var shownGlow: Double?

    /// Called on every frame while the menu is open. A change too small to see isn't drawn, so a
    /// steady logo costs nothing.
    func show(glow: Double) {
        if let shownGlow, abs(glow - shownGlow) < 0.002 { return }
        shownGlow = glow
        withoutAnimation {
            logo.opacity = Float(glow)
            logo.shadowOpacity = Float(glow)
        }
    }

    private func withoutAnimation(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}

/// A rounded, slightly raised group of rows, like a module in Control Center.
private final class Card: NSView {
    /// The rows, without the card's background (e.g. to fade them).
    let rows = NSStackView()

    init() {
        super.init(frame: .zero)
        rows.orientation = .vertical
        rows.alignment = .width
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func add(_ views: [NSView]) {
        views.forEach(rows.addArrangedSubview)
    }

    override func draw(_ dirtyRect: NSRect) {
        GlassMaterial.draw(in: bounds, radius: ControlPanel.cardRadius, appearance: effectiveAppearance)
    }
}

/// The live view in a group of its own, as a Control Center module holds its control.
private final class PreviewWell: NSView {
    init(content: NSView) {
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        GlassMaterial.draw(in: bounds, radius: ControlPanel.cardRadius, appearance: effectiveAppearance, recessed: true)
    }
}

/// The glass the panel's groups are drawn on: the lit, translucent material macOS 26 and later use for
/// Control Center's modules.
///
/// Drawn rather than made with `NSGlassEffectView`, for two reasons: a glass view draws as a blank
/// shape into a picture (the README's are made that way, by `PanelRenderer`), and a menu is glass
/// itself, which the system asks glass not to sit on.
private enum GlassMaterial {
    /// Fills `rect` with glass: a soft gradient, and a hairline rim that's lit at the top and fades
    /// toward the bottom, as light falls on an edge. `recessed` turns both around for a well that
    /// looks cut into the panel, e.g. for the live view.
    static func draw(in rect: NSRect, radius: CGFloat, appearance: NSAppearance, recessed: Bool = false) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let body = CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius - 0.5,
                          cornerHeight: radius - 0.5, transform: nil)

        context.saveGState()
        context.addPath(body)
        context.clip()
        let fill: [CGColor]
        if recessed {
            fill = isDark
                ? [NSColor(white: 0, alpha: 0.22).cgColor, NSColor(white: 0, alpha: 0.12).cgColor]
                : [NSColor(white: 0, alpha: 0.06).cgColor, NSColor(white: 0, alpha: 0.03).cgColor]
        } else {
            fill = isDark
                ? [NSColor(white: 1, alpha: 0.155).cgColor, NSColor(white: 1, alpha: 0.075).cgColor]
                : [NSColor(white: 1, alpha: 0.92).cgColor, NSColor(white: 1, alpha: 0.7).cgColor]
        }
        draw(fill, in: context, from: CGPoint(x: rect.midX, y: rect.minY), to: CGPoint(x: rect.midX, y: rect.maxY))
        context.restoreGState()

        context.saveGState()
        context.addPath(body)
        context.setLineWidth(1)
        context.replacePathWithStrokedPath()
        context.clip()
        let rim: [CGColor]
        if recessed {
            rim = isDark
                ? [NSColor(white: 0, alpha: 0.45).cgColor, NSColor(white: 1, alpha: 0.06).cgColor]
                : [NSColor(white: 0, alpha: 0.14).cgColor, NSColor(white: 1, alpha: 0.5).cgColor]
        } else {
            rim = isDark
                ? [NSColor(white: 1, alpha: 0.26).cgColor, NSColor(white: 1, alpha: 0.04).cgColor]
                : [NSColor(white: 0, alpha: 0.10).cgColor, NSColor(white: 0, alpha: 0.02).cgColor]
        }
        draw(rim, in: context, from: CGPoint(x: rect.midX, y: rect.minY), to: CGPoint(x: rect.midX, y: rect.maxY))
        context.restoreGState()
    }

    /// A linear gradient straight down `from` the top `to` the bottom.
    static func draw(_ colors: [CGColor], in context: CGContext, from start: CGPoint, to end: CGPoint) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray,
                                        locations: [0, 1])
        else { return }
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
    }
}


/// A hairline between rows that starts under the row's text, as in iOS Settings.
private final class Separator: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 1) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        let thickness = 1 / (window?.backingScaleFactor ?? 2)
        let start = ControlPanel.textColumn
        NSRect(x: start, y: 0, width: max(0, bounds.width - start - ControlPanel.switchInset), height: thickness).fill()
    }
}

/// A white symbol on a coloured rounded square, like the icons in System Settings.
private final class IconTile: NSView {
    private let color: NSColor
    var isDimmed = false { didSet { alphaValue = isDimmed ? 0.35 : 1 } }

    init(symbol: String, color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true // so it fades with `alphaValue` where the logo is, or isn't, supported
        let image = NSImageView(image: ControlPanel.symbol(symbol, size: 12) ?? NSImage())
        image.contentTintColor = .white
        image.translatesAutoresizingMaskIntoConstraints = false
        addSubview(image)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: ControlPanel.tileSize),
            heightAnchor.constraint(equalToConstant: ControlPanel.tileSize),
            image.centerXAnchor.constraint(equalTo: centerXAnchor),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = 6.5
        let tile = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        // Lit from above, as the system's own icons are.
        NSGradient(starting: color.blended(withFraction: 0.3, of: .white) ?? color, ending: color)?
            .draw(in: tile, angle: -90)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setLineWidth(1)
        context.replacePathWithStrokedPath()
        context.clip()
        GlassMaterial.draw([NSColor(white: 1, alpha: 0.28).cgColor, NSColor(white: 1, alpha: 0.02).cgColor],
                           in: context, from: CGPoint(x: bounds.midX, y: bounds.minY),
                           to: CGPoint(x: bounds.midX, y: bounds.maxY))
        context.restoreGState()
    }
}

/// The state of one of the panel's switches: what it shows, whether it takes clicks, and what to tell
/// the panel when the user flips it.
@MainActor
private final class SwitchState: ObservableObject {
    @Published var isOn: Bool
    @Published var isEnabled = true
    /// Called when the user flips it, not when the panel sets it.
    var onChange: ((Bool) -> Void)?

    init(isOn: Bool) {
        self.isOn = isOn
    }
}

private struct SwitchView: View {
    @ObservedObject var state: SwitchState
    let label: String

    var body: some View {
        Toggle(label, isOn: Binding(
            get: { state.isOn },
            set: { newValue in
                state.isOn = newValue // the knob moves at once, before the logo has faded
                state.onChange?(newValue)
            }
        ))
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
        // Not `.disabled`: SwiftUI would draw it faint over the row the panel has already greyed,
        // and a switch that only looks disabled is what the panel wants here.
        .allowsHitTesting(state.isEnabled)
        .accessibilityLabel(label)
    }
}

/// A switch as System Settings has one: the system's own toggle, at the small control size. (AppKit's
/// `NSSwitch` is 54 wide with a round knob; a settings row's is 36 with a rounded one.)
@MainActor
private final class SwitchToggle: NSView {
    let state: SwitchState
    private let host: NSHostingView<SwitchView>

    init(isOn: Bool, label: String) {
        state = SwitchState(isOn: isOn)
        host = NSHostingView(rootView: SwitchView(state: state, label: label))
        super.init(frame: .zero)
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            setContentHuggingPriority(.required, for: orientation)
            setContentCompressionResistancePriority(.required, for: orientation)
        }
        // A little room around the toggle, so its focus ring isn't clipped.
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 38),
            heightAnchor.constraint(equalToConstant: 22),
            host.centerXAnchor.constraint(equalTo: centerXAnchor),
            host.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isOn: Bool { state.isOn }
    var onChange: ((Bool) -> Void)? {
        get { state.onChange }
        set { state.onChange = newValue }
    }
    var isEnabled: Bool {
        get { state.isEnabled }
        set { state.isEnabled = newValue }
    }

    /// Sets the switch without telling the panel, animating the knob when asked.
    func set(on: Bool, animated: Bool) {
        guard state.isOn != on else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) { state.isOn = on }
        } else {
            state.isOn = on
        }
    }
}

/// A slider that knows while it's being dragged, so the panel leaves the knob where the pointer has it
/// when the logo's brightness arrives. (`NSSlider` keeps that to itself.)
private final class TrackingSlider: NSSlider {
    private(set) var isTracking = false

    override func mouseDown(with event: NSEvent) {
        isTracking = true
        super.mouseDown(with: event) // returns when the drag ends
        isTracking = false
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
                   canFollowSound: Bool = true, followsBattery: Bool = false,
                   breathesWhileCharging: Bool = false) -> PanelState {
            let status = LogoStatus(isSupported: isSupported, setting: isSupported ? setting : nil, source: .daemon,
                                    isLit: setting == .on, outputLevel: 0.2)
            return PanelState(status: status, canControlDirectly: canControlDirectly, canFollowSound: canFollowSound,
                              effect: options.effect, brightness: options.brightness, followsBattery: followsBattery,
                              breathesWhileCharging: breathesWhileCharging)
        }
        let on = state(.on)
        var looping = on
        looping.morse = MorseMessage(text: "SOS", loops: true)
        looping.morseLoops = true
        let states = [("on", on), ("morse", looping), ("off", state(.off)), ("battery", state(.on, followsBattery: true)),
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
        if options.icon, let symbol = NSImage(systemSymbolName: on.symbolName, accessibilityDescription: nil) {
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
            y = addItem("Lit with Lid Closed", subtitle: "On power or a display", at: y)
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

    /// Says which visible one-line labels are narrower than their text, so a narrower panel can be checked.
    private static func reportTruncatedLabels(in view: NSView, path: String) {
        for subview in view.subviews where !subview.isHiddenOrHasHiddenAncestor {
            // Both widths are without the label's own padding (its alignment rect).
            if let label = subview as? NSTextField, label.cell?.wraps == false {
                let width = label.alignmentRect(forFrame: label.frame).width
                if width < label.intrinsicContentSize.width - 0.5 {
                    print("\(path): \"\(label.stringValue)\" is truncated (\(width) of \(label.intrinsicContentSize.width) pt)")
                }
            } else if let label = subview as? NSTextField {
                // A wrapping label cut to fewer lines than it needs drops its last words silently.
                let rect = label.alignmentRect(forFrame: label.frame)
                let needed = label.attributedStringValue.boundingRect(
                    with: NSSize(width: rect.width, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading]
                ).height.rounded(.up)
                if rect.height < needed - 0.5 {
                    print("\(path): \"\(label.stringValue)\" is cut (\(rect.height) of \(needed) pt high)")
                }
            }
            reportTruncatedLabels(in: subview, path: path)
        }
    }
}

private extension LogoPreview {
    /// The live view's size without the panel around it: just the lid.
    static var renderedLidSize: NSSize { lidSize }

    /// Where the lid is drawn in the view (centred at the top, as `layout()` places it).
    var renderedLidFrame: NSRect {
        NSRect(x: (bounds.width - Self.lidSize.width) / 2, y: 0, width: Self.lidSize.width, height: Self.lidSize.height)
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
