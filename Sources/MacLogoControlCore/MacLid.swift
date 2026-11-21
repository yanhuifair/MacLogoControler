import Foundation

/// The size of this Mac's lid, so the live view can look like the real lid — the 14-inch and
/// 16-inch MacBook Pros draw a little differently.
///
/// The same device model code `MacFinish` reads carries the screen size: "…-2026-14-space-black"
/// and "…-2026-16-space-black" differ by nothing else.
public enum MacLid: Sendable, Equatable, Hashable, CaseIterable {
    case fourteen
    case sixteen

    /// This Mac's lid, or `nil` if it can't be told.
    public static func current() -> MacLid? {
        MacFinish.deviceType().flatMap { MacLid(deviceTypeIdentifier: $0.identifier) }
    }

    /// The screen size in a device type identifier, "-14-" or "-16-". `nil` for anything else.
    public init?(deviceTypeIdentifier identifier: String) {
        let name = identifier.lowercased()
        if name.contains("-14-") {
            self = .fourteen
        } else if name.contains("-16-") {
            self = .sixteen
        } else {
            return nil
        }
    }

    /// What the panel's size tab shows.
    public var title: String {
        switch self {
        case .fourteen: "14″"
        case .sixteen: "16″"
        }
    }
}
