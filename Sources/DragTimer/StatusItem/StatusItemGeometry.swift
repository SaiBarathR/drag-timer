import AppKit

/// Shared status-item geometry. Keeping measurement and anchor calculations in
/// one place prevents the drawn clock, reserved menu-bar width, and popover
/// chevron from drifting apart.
enum StatusItemGeometry {
    static let collapsedWidth: CGFloat = 32
    static let iconDiameter: CGFloat = 14
    static let iconLeading: CGFloat = 6
    static let textLeading: CGFloat = 26
    static let textTrailing: CGFloat = 7
    static let countdownFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)

    static func width(for countdownText: String?) -> CGFloat {
        guard let countdownText else { return collapsedWidth }
        let textWidth = measuredWidth(of: countdownText)
        return ceil(textLeading + textWidth + textTrailing)
    }

    static func iconRect(in bounds: NSRect, hasCountdownLayout: Bool) -> NSRect {
        let centerX = hasCountdownLayout
            ? bounds.minX + iconLeading + (iconDiameter / 2)
            : bounds.midX
        return NSRect(
            x: centerX - (iconDiameter / 2),
            y: bounds.midY - (iconDiameter / 2),
            width: iconDiameter,
            height: iconDiameter
        )
    }

    /// Uses the clock's horizontal footprint while retaining the status view's
    /// full height, so the chevron targets the clock without moving its tip
    /// away from the bottom edge of the menu bar.
    static func popoverAnchorRect(in bounds: NSRect, hasCountdownLayout: Bool) -> NSRect {
        let iconRect = iconRect(in: bounds, hasCountdownLayout: hasCountdownLayout)
        return NSRect(
            x: iconRect.minX,
            y: bounds.minY,
            width: iconRect.width,
            height: bounds.height
        )
    }

    static func measuredWidth(of text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: countdownFont]).width
    }
}
