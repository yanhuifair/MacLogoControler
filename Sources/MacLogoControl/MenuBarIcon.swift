import AppKit
import MacLogoControlCore

/// The menu bar item's icon: the Apple logo whose backlight this app controls, in the menu bar's colour
/// (a template image), and dimmed while it isn't lit.
enum MenuBarIcon {
    /// SF Symbols' Apple logo. There's no lit or outline version of it, so the item is dimmed instead
    /// when the logo is off: a dimmed `appearsDisabled` item is what macOS does for one that's unusable.
    static let symbolName = "apple.logo"

    /// The icon for `state`, and whether the item should look disabled.
    static func image(for state: PanelState) -> (image: NSImage?, isDimmed: Bool) {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: state.symbolDescription)
        image?.isTemplate = true
        return (image, state.isDimmed)
    }
}
