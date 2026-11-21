import Foundation

/// What the menu shows: the menu bar icon, and the control panel with which of its parts can be used.
///
/// It's worked out from the logo's status and the user's choices, so the rules can be tested without
/// AppKit.
public struct PanelState: Equatable, Sendable {
    /// Whether this Mac has the illuminated logo.
    public var isSupported: Bool
    /// Whether the logo switch shows on: the setting asked for while a switch is under way, otherwise
    /// the current one. An unknown setting counts as on.
    public var isOn: Bool
    /// Waiting for a password or `sudo` (the fallback path, which can't take another change meanwhile).
    public var isBusy: Bool
    /// Whether the brightness and the effects are shown. They need direct control.
    public var showsAdjustments: Bool
    /// Whether the Sound effect is among them: the sound can be heard on this Mac (macOS 14.2 or later).
    public var showsSound: Bool
    public var effect: LogoEffect
    /// The brightness the slider shows: the chosen one, or the battery's charge while it's followed.
    public var brightness: Double
    /// Whether the brightness follows the battery's charge (the Battery switch).
    public var followsBattery: Bool
    /// Whether it follows the display's brightness, and so the light around you (the Automatic switch).
    public var followsDisplayBrightness: Bool
    /// Whether the logo breathes while the battery charges (the Charging switch).
    public var breathesWhileCharging: Bool
    /// Whether the logo stays lit with the lid closed (the Lid Closed switch), and whether that switch
    /// is shown: it needs corebrightnessd, which the app only has with direct control.
    public var lightsWithLidClosed: Bool
    public var showsLidClosedOption: Bool
    /// The Morse message being sent, if any.
    public var morse: MorseMessage?
    /// Whether Morse code repeats until it's stopped (the loop switch).
    public var morseLoops: Bool
    /// The only text in the panel: why everything is disabled, on a Mac without the logo.
    public var message: String?
    /// What the menu bar item is showing, for its tooltip and VoiceOver.
    public var symbolDescription: String
    /// Whether the menu bar item is drawn dimmed: the logo off, or a Mac without one.
    public var isDimmed: Bool

    /// `requested` is the setting asked for while a switch is under way, which the panel and the icon show
    /// straight away, so the rest of the panel follows the switch at once instead of when the fade ends.
    public init(status: LogoStatus, requested: LogoIllumination? = nil, canControlDirectly: Bool,
                canFollowSound: Bool = true, effect: LogoEffect, brightness: Double, followsBattery: Bool = false,
                followsDisplayBrightness: Bool = false, breathesWhileCharging: Bool = false,
                lightsWithLidClosed: Bool = false, showsLidClosedOption: Bool = true, isBusy: Bool = false,
                morse: MorseMessage? = nil, morseLoops: Bool = false) {
        let setting = requested ?? status.setting
        isSupported = status.isSupported
        isOn = status.isSupported && setting != .off
        self.isBusy = isBusy
        showsAdjustments = status.isSupported && canControlDirectly
        showsSound = showsAdjustments && canFollowSound
        self.effect = effect
        self.brightness = brightness
        self.followsBattery = followsBattery
        self.followsDisplayBrightness = followsDisplayBrightness
        self.breathesWhileCharging = breathesWhileCharging
        self.lightsWithLidClosed = lightsWithLidClosed
        self.showsLidClosedOption = showsLidClosedOption && showsAdjustments
        self.morse = canControlDirectly ? morse : nil
        self.morseLoops = morseLoops
        message = status.isSupported ? nil : "Needs a MacBook Pro with PROLED XDR Display"
        (symbolDescription, isDimmed) = switch (status.isSupported, setting) {
        case (false, _): ("No illuminated logo on this Mac", true)
        case (true, .off): ("Logo illumination off", true)
        case (true, .on): ("Logo illumination on", false)
        case (true, nil): ("Logo illumination unknown", false)
        }
    }

    /// Whether the logo switch takes clicks. It looks disabled otherwise.
    public var canSwitch: Bool { isSupported && !isBusy }

    /// Whether the brightness, the Battery and Charging switches and the effects can be changed: only
    /// while the logo is (or is being turned) on. Otherwise they're greyed out, and keep their values for
    /// when it's back on.
    public var canAdjust: Bool { showsAdjustments && isOn }

    /// Whether the brightness slider can be moved: as for the rest, and not while the display or the
    /// battery sets the brightness. It's greyed out then, showing the level they give.
    public var canChangeBrightness: Bool { canAdjust && !followsBattery && !followsDisplayBrightness }

    /// Whether a Morse message is being sent, so the play button shows stop.
    public var isSendingMorse: Bool { morse != nil }
}
