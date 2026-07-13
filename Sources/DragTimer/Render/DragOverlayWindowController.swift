import AppKit
import QuartzCore

private final class DragOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DragOverlayWindowController {
    private let panel: DragOverlayPanel
    private let surface: DragSurfaceView

    init(countdownScale: CountdownScale = .standard, highContrast: Bool = false) {
        let frame = Self.allScreenFrame()
        panel = DragOverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        surface = DragSurfaceView(
            frame: NSRect(origin: .zero, size: frame.size),
            countdownScale: countdownScale,
            highContrast: highContrast
        )

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
        isSnapped: Bool,
        updateText: Bool
    ) {
        let localOrigin = localPoint(for: originScreen)
        let localCursor = localPoint(for: cursorScreen)
        surface.render(
            origin: localOrigin,
            cursor: localCursor,
            duration: duration,
            isSnapped: isSnapped,
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
    private let countdownScale: CountdownScale
    private let highContrast: Bool
    // The line assembly lives inside a container rotated around the origin, so
    // per-frame updates are transform and bounds changes — the tick path is
    // rebuilt only when the number of visible ticks changes.
    private let lineContainer = CALayer()
    private let glowLayer = CAGradientLayer()
    private let strokeLayer = CAGradientLayer()
    private let ticksLayer = CAShapeLayer()

    private let originRingLayer = CALayer()
    private let endpointHaloLayer = CALayer()
    private let endpointLayer = CALayer()
    private let endpointCoreLayer = CALayer()

    private let labelBackingLayer = CALayer()
    private let labelLayer = CATextLayer()

    private var appliedSnapState: Bool?
    private var lastTickCount = -1
    private var labelWidth: CGFloat = 132

    private enum Metrics {
        static let containerHeight: CGFloat = 44
        static let strokeHeight: CGFloat = 3
        static let strokeHeightSnapped: CGFloat = 4
        static let glowHeight: CGFloat = 11
        static let glowHeightSnapped: CGFloat = 15
        static let tickSpacing: CGFloat = 28
        static let tickHalfHeight: CGFloat = 3.5
        static let tickLeadingOffset: CGFloat = 26
        static let tickTrailingMargin: CGFloat = 32
        static let labelHeight: CGFloat = 58
    }

    private static var accentColor: NSColor { .controlAccentColor }
    private static var snapColor: NSColor { .systemMint }

    init(frame frameRect: NSRect, countdownScale: CountdownScale, highContrast: Bool) {
        self.countdownScale = countdownScale
        self.highContrast = highContrast
        super.init(frame: frameRect)
        configureLayers()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        labelLayer.contentsScale = scale
        ticksLayer.contentsScale = scale
    }

    func render(
        origin: CGPoint,
        cursor: CGPoint,
        duration: TimeInterval,
        isSnapped: Bool,
        updateText: Bool
    ) {
        let dx = cursor.x - origin.x
        let dy = cursor.y - origin.y
        let length = max(1, hypot(dx, dy))
        let angle = atan2(dy, dx)
        let snapStateChanged = appliedSnapState != isSnapped

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        layoutLine(origin: origin, length: length, angle: angle, isSnapped: isSnapped)

        originRingLayer.position = origin
        endpointLayer.position = cursor
        endpointCoreLayer.position = cursor
        endpointHaloLayer.position = cursor

        if snapStateChanged {
            applySnapAppearance(isSnapped)
        }

        layoutLabel(cursor: cursor)

        if updateText {
            updateLabelText(duration: duration, isSnapped: isSnapped)
        }

        CATransaction.commit()

        if snapStateChanged {
            if isSnapped, appliedSnapState != nil {
                pulseEndpoint()
            }
            appliedSnapState = isSnapped
        }
    }

    // MARK: - Per-frame layout

    private func layoutLine(origin: CGPoint, length: CGFloat, angle: CGFloat, isSnapped: Bool) {
        let height = Metrics.containerHeight
        let midY = height / 2

        lineContainer.position = origin
        lineContainer.bounds = CGRect(x: 0, y: 0, width: length, height: height)
        lineContainer.setAffineTransform(CGAffineTransform(rotationAngle: angle))

        let strokeHeight = isSnapped ? Metrics.strokeHeightSnapped : Metrics.strokeHeight
        strokeLayer.frame = CGRect(x: 0, y: midY - strokeHeight / 2, width: length, height: strokeHeight)
        strokeLayer.cornerRadius = strokeHeight / 2

        let glowHeight = isSnapped ? Metrics.glowHeightSnapped : Metrics.glowHeight
        glowLayer.frame = CGRect(x: 0, y: midY - glowHeight / 2, width: length, height: glowHeight)
        glowLayer.cornerRadius = glowHeight / 2

        ticksLayer.frame = lineContainer.bounds
        let usableLength = length - Metrics.tickLeadingOffset - Metrics.tickTrailingMargin
        let tickCount = max(0, Int(usableLength / Metrics.tickSpacing) + 1)
        if tickCount != lastTickCount {
            lastTickCount = tickCount
            ticksLayer.path = Self.tickPath(count: tickCount, midY: midY)
        }
    }

    private func layoutLabel(cursor: CGPoint) {
        let labelHeight = Metrics.labelHeight * countdownScale.factor
        let x = min(max(10, cursor.x - labelWidth / 2), max(10, bounds.width - labelWidth - 10))
        let y = min(max(10, cursor.y - 80), max(10, bounds.height - labelHeight - 10))
        let labelFrame = CGRect(x: x, y: y, width: labelWidth, height: labelHeight)
        labelBackingLayer.frame = labelFrame
        labelBackingLayer.cornerRadius = labelHeight / 2

        let textHeight: CGFloat = 40 * countdownScale.factor
        labelLayer.frame = CGRect(
            x: labelFrame.minX,
            y: labelFrame.midY - textHeight / 2 - 1,
            width: labelFrame.width,
            height: textHeight
        )
    }

    private func updateLabelText(duration: TimeInterval, isSnapped: Bool) {
        let durationString = DurationText.dragSelection(duration)
        let fireTimeString = "at \(TimerDateText.fireTime(after: duration))"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 2
        let text = NSMutableAttributedString(
            string: durationString,
            attributes: [
                .font: labelFont,
                .foregroundColor: isSnapped ? NSColor.white : NSColor(white: 0.96, alpha: 1),
                .kern: 0.35,
                .paragraphStyle: paragraph
            ]
        )
        text.append(NSAttributedString(
            string: "\n\(fireTimeString)",
            attributes: [
                .font: fireTimeFont,
                .foregroundColor: isSnapped
                    ? NSColor.white.withAlphaComponent(0.88)
                    : NSColor(white: 0.82, alpha: 1),
                .kern: 0.2,
                .paragraphStyle: paragraph
            ]
        ))
        labelLayer.string = text
        let measuredWidth = max(
            ceil((durationString as NSString).size(withAttributes: [.font: labelFont]).width),
            ceil((fireTimeString as NSString).size(withAttributes: [.font: fireTimeFont]).width)
        ) + 38
        labelWidth = max(124, measuredWidth)
    }

    // MARK: - Snap state

    private func applySnapAppearance(_ isSnapped: Bool) {
        let accent = isSnapped ? Self.snapColor : Self.accentColor

        strokeLayer.colors = [
            accent.withAlphaComponent(0.25).cgColor,
            accent.withAlphaComponent(0.85).cgColor,
            accent.cgColor
        ]
        glowLayer.colors = [
            accent.withAlphaComponent(0.0).cgColor,
            accent.withAlphaComponent(isSnapped ? 0.30 : 0.18).cgColor,
            accent.withAlphaComponent(isSnapped ? 0.42 : 0.26).cgColor
        ]
        ticksLayer.strokeColor = accent.withAlphaComponent(0.55).cgColor

        originRingLayer.borderColor = accent.withAlphaComponent(0.85).cgColor
        originRingLayer.backgroundColor = accent.withAlphaComponent(0.22).cgColor

        let endpointSize: CGFloat = isSnapped ? 30 : 24
        endpointLayer.bounds.size = CGSize(width: endpointSize, height: endpointSize)
        endpointLayer.cornerRadius = endpointSize / 2
        endpointLayer.backgroundColor = accent.withAlphaComponent(isSnapped ? 0.30 : 0.20).cgColor
        endpointLayer.borderColor = accent.cgColor
        endpointLayer.borderWidth = isSnapped ? 2.5 : 2
        endpointLayer.shadowColor = accent.cgColor
        endpointLayer.shadowOpacity = isSnapped ? 0.65 : 0.45

        let coreSize: CGFloat = isSnapped ? 9 : 7
        endpointCoreLayer.bounds.size = CGSize(width: coreSize, height: coreSize)
        endpointCoreLayer.cornerRadius = coreSize / 2

        endpointHaloLayer.borderColor = accent.cgColor

        labelBackingLayer.borderColor = isSnapped
            ? accent.withAlphaComponent(0.9).cgColor
            : NSColor.white.withAlphaComponent(0.16).cgColor
        labelBackingLayer.borderWidth = isSnapped ? 1.5 : 1
    }

    private func pulseEndpoint() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }

        let haloSize: CGFloat = 30
        endpointHaloLayer.bounds = CGRect(x: 0, y: 0, width: haloSize, height: haloSize)
        endpointHaloLayer.cornerRadius = haloSize / 2

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.7
        scale.toValue = 1.9
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0.0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.45
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = true
        endpointHaloLayer.opacity = 0
        endpointHaloLayer.add(group, forKey: "snapPulse")

        let bump = CASpringAnimation(keyPath: "transform.scale")
        bump.fromValue = 1.25
        bump.toValue = 1.0
        bump.damping = 12
        bump.stiffness = 320
        bump.duration = bump.settlingDuration
        endpointLayer.add(bump, forKey: "snapBump")
    }

    // MARK: - Setup

    private func configureLayers() {
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.clear.cgColor

        lineContainer.anchorPoint = CGPoint(x: 0, y: 0.5)
        lineContainer.bounds = CGRect(x: 0, y: 0, width: 1, height: Metrics.containerHeight)

        glowLayer.startPoint = CGPoint(x: 0, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1, y: 0.5)
        strokeLayer.startPoint = CGPoint(x: 0, y: 0.5)
        strokeLayer.endPoint = CGPoint(x: 1, y: 0.5)

        ticksLayer.fillColor = nil
        ticksLayer.lineWidth = highContrast ? 1.8 : 1
        ticksLayer.lineCap = .round

        originRingLayer.bounds = CGRect(x: 0, y: 0, width: 11, height: 11)
        originRingLayer.cornerRadius = 5.5
        originRingLayer.borderWidth = 1.5

        endpointHaloLayer.backgroundColor = NSColor.clear.cgColor
        endpointHaloLayer.borderWidth = 2
        endpointHaloLayer.opacity = 0

        endpointLayer.shadowRadius = 10
        endpointLayer.shadowOffset = .zero

        endpointCoreLayer.backgroundColor = NSColor.white.cgColor

        labelBackingLayer.backgroundColor = NSColor(
            calibratedRed: 0.07,
            green: 0.075,
            blue: 0.10,
            alpha: highContrast ? 1 : 0.88
        ).cgColor
        labelBackingLayer.shadowColor = NSColor.black.cgColor
        labelBackingLayer.shadowOpacity = 0.35
        labelBackingLayer.shadowRadius = 14
        labelBackingLayer.shadowOffset = CGSize(width: 0, height: -4)

        labelLayer.alignmentMode = .center
        labelLayer.isWrapped = true
        labelLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2

        applySnapAppearance(false)

        lineContainer.addSublayer(glowLayer)
        lineContainer.addSublayer(strokeLayer)
        lineContainer.addSublayer(ticksLayer)

        layer?.addSublayer(lineContainer)
        layer?.addSublayer(originRingLayer)
        layer?.addSublayer(endpointHaloLayer)
        layer?.addSublayer(endpointLayer)
        layer?.addSublayer(endpointCoreLayer)
        layer?.addSublayer(labelBackingLayer)
        layer?.addSublayer(labelLayer)
    }

    private static func tickPath(count: Int, midY: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for index in 0..<count {
            let x = Metrics.tickLeadingOffset + CGFloat(index) * Metrics.tickSpacing
            path.move(to: CGPoint(x: x, y: midY - Metrics.tickHalfHeight))
            path.addLine(to: CGPoint(x: x, y: midY + Metrics.tickHalfHeight))
        }
        return path
    }

    private var labelFont: NSFont {
        let size = 16 * countdownScale.factor
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: highContrast ? .bold : .semibold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded),
              let rounded = NSFont(descriptor: descriptor, size: size) else {
            return base
        }
        return rounded
    }

    private var fireTimeFont: NSFont {
        NSFont.monospacedDigitSystemFont(
            ofSize: 12 * countdownScale.factor,
            weight: highContrast ? .semibold : .medium
        )
    }
}
