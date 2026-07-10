import AppKit
import Foundation
import QuartzCore

/// CADisplayLink is intentionally created only while a drag is active. Mouse
/// events update physics input; this type is the sole owner of visual cadence.
final class DisplayLinkDriver: NSObject {
    var onFrame: ((TimeInterval, TimeInterval) -> Void)?

    private var displayLink: CADisplayLink?
    private var lastTargetTimestamp: CFTimeInterval?
    private var displayID: UInt32?

    var isRunning: Bool { displayLink != nil }

    func start(on screen: NSScreen?) {
        guard displayLink == nil else { return }
        guard let screen else { return }
        let link = screen.displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        link.add(to: .main, forMode: .common)
        link.add(to: .main, forMode: .eventTracking)
        displayLink = link
        displayID = Self.displayIdentifier(for: screen)
    }

    func retarget(to screen: NSScreen?) {
        guard let screen else { return }
        let newDisplayID = Self.displayIdentifier(for: screen)
        guard newDisplayID != displayID else { return }
        stop()
        start(on: screen)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTargetTimestamp = nil
        displayID = nil
    }

    @objc private func displayLinkDidFire(_ link: CADisplayLink) {
        let timestamp = link.targetTimestamp
        let fallbackElapsed = max(1.0 / 240.0, link.targetTimestamp - link.timestamp)
        let elapsed = lastTargetTimestamp.map { max(1.0 / 240.0, timestamp - $0) } ?? fallbackElapsed
        lastTargetTimestamp = timestamp
        onFrame?(elapsed, timestamp)
    }

    private static func displayIdentifier(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
