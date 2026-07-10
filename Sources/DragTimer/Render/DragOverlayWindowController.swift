import AppKit
import QuartzCore

private final class DragOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DragOverlayWindowController {
    private let panel: DragOverlayPanel
    private let surface: DragSurfaceView

    init() {
        let frame = Self.allScreenFrame()
        panel = DragOverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        surface = DragSurfaceView(frame: NSRect(origin: .zero, size: frame.size))

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = surface
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func render(
        originScreen: CGPoint,
        cursorScreen: CGPoint,
        duration: TimeInterval,
        updateText: Bool
    ) {
        let localOrigin = localPoint(for: originScreen)
        let localCursor = localPoint(for: cursorScreen)
        surface.render(
            origin: localOrigin,
            cursor: localCursor,
            duration: duration,
            updateText: updateText
        )
    }

    private func localPoint(for screenPoint: CGPoint) -> CGPoint {
        CGPoint(x: screenPoint.x - panel.frame.minX, y: screenPoint.y - panel.frame.minY)
    }

    private static func allScreenFrame() -> NSRect {
        guard let firstScreen = NSScreen.screens.first else {
            return NSRect(x: 0, y: 0, width: 1, height: 1)
        }
        return NSScreen.screens.dropFirst().reduce(firstScreen.frame) { partialResult, screen in
            partialResult.union(screen.frame)
        }
    }
}

private final class DragSurfaceView: NSView {
    private let glowLayer = CALayer()
    private let lineLayer = CALayer()
    private let endpointLayer = CALayer()
    private let endpointCoreLayer = CALayer()
    private let labelBackingLayer = CALayer()
    private let labelLayer = CATextLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        labelLayer.contentsScale = scale
    }

    func render(origin: CGPoint, cursor: CGPoint, duration: TimeInterval, updateText: Bool) {
        let dx = cursor.x - origin.x
        let dy = cursor.y - origin.y
        let length = max(1, hypot(dx, dy))
        let angle = atan2(dy, dx)
        let transform = CGAffineTransform(rotationAngle: angle)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        updateLine(glowLayer, origin: origin, length: length, transform: transform)
        updateLine(lineLayer, origin: origin, length: length, transform: transform)

        endpointLayer.position = cursor
        endpointCoreLayer.position = cursor

        let labelWidth: CGFloat = 126
        let labelHeight: CGFloat = 38
        let x = min(max(8, cursor.x - labelWidth / 2), max(8, bounds.width - labelWidth - 8))
        let y = min(max(8, cursor.y - 52), max(8, bounds.height - labelHeight - 8))
        let labelFrame = CGRect(x: x, y: y, width: labelWidth, height: labelHeight)
        labelBackingLayer.frame = labelFrame
        labelLayer.frame = labelFrame.insetBy(dx: 6, dy: 7)

        if updateText {
            labelLayer.string = NSAttributedString(
                string: DurationText.compact(duration),
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 17, weight: .semibold),
                    .foregroundColor: NSColor.white
                ]
            )
        }

        CATransaction.commit()
    }

    private func configureLayers() {
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.clear.cgColor

        configureLine(glowLayer, color: NSColor.systemIndigo.withAlphaComponent(0.2).cgColor, thickness: 12)
        configureLine(lineLayer, color: NSColor.systemIndigo.cgColor, thickness: 2)

        endpointLayer.bounds = CGRect(x: 0, y: 0, width: 22, height: 22)
        endpointLayer.cornerRadius = 11
        endpointLayer.backgroundColor = NSColor(calibratedWhite: 0.05, alpha: 0.96).cgColor
        endpointLayer.borderColor = NSColor.systemIndigo.withAlphaComponent(0.8).cgColor
        endpointLayer.borderWidth = 1.5
        endpointLayer.shadowColor = NSColor.systemIndigo.cgColor
        endpointLayer.shadowOpacity = 0.45
        endpointLayer.shadowRadius = 9
        endpointLayer.shadowOffset = .zero

        endpointCoreLayer.bounds = CGRect(x: 0, y: 0, width: 6, height: 6)
        endpointCoreLayer.cornerRadius = 3
        endpointCoreLayer.backgroundColor = NSColor.white.withAlphaComponent(0.95).cgColor

        labelBackingLayer.backgroundColor = NSColor(calibratedRed: 0.055, green: 0.06, blue: 0.10, alpha: 0.96).cgColor
        labelBackingLayer.cornerRadius = 12
        labelBackingLayer.borderWidth = 1
        labelBackingLayer.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        labelBackingLayer.shadowColor = NSColor.black.cgColor
        labelBackingLayer.shadowOpacity = 0.32
        labelBackingLayer.shadowRadius = 12
        labelBackingLayer.shadowOffset = CGSize(width: 0, height: -3)

        labelLayer.alignmentMode = .center
        labelLayer.foregroundColor = NSColor.white.cgColor
        labelLayer.fontSize = 17
        labelLayer.isWrapped = false
        labelLayer.shadowColor = NSColor.black.cgColor
        labelLayer.shadowOpacity = 0.6
        labelLayer.shadowRadius = 1
        labelLayer.shadowOffset = CGSize(width: 0, height: -1)
        labelLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2

        layer?.addSublayer(glowLayer)
        layer?.addSublayer(lineLayer)
        layer?.addSublayer(endpointLayer)
        layer?.addSublayer(endpointCoreLayer)
        layer?.addSublayer(labelBackingLayer)
        layer?.addSublayer(labelLayer)
    }

    private func configureLine(_ layer: CALayer, color: CGColor, thickness: CGFloat) {
        layer.anchorPoint = CGPoint(x: 0, y: 0.5)
        layer.bounds = CGRect(x: 0, y: 0, width: 1, height: thickness)
        layer.cornerRadius = thickness / 2
        layer.backgroundColor = color
    }

    private func updateLine(_ layer: CALayer, origin: CGPoint, length: CGFloat, transform: CGAffineTransform) {
        layer.position = origin
        layer.bounds.size.width = length
        layer.setAffineTransform(transform)
    }
}
