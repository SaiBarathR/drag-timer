import Foundation

enum FeelPreset: String, Codable, CaseIterable, Identifiable {
    case precise
    case snappy
    case throwable
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .precise: return "Precise"
        case .snappy: return "Snappy"
        case .throwable: return "Throwable"
        case .custom: return "Custom"
        }
    }
}

struct DragPhysicsSettings: Codable, Equatable {
    var minimumDuration: TimeInterval = 60
    var maximumDuration: TimeInterval = 4 * 60 * 60
    var referenceDistance: Double = 560
    var gamma: Double = 1.68
    var inertiaStrength: Double = 0.075
    var springStiffness: Double = 190
    var springDamping: Double = 20
    var snappingEnabled: Bool = true
    var snapTolerance: TimeInterval = 24
    var reduceMotion: Bool = false

    static func forPreset(_ preset: FeelPreset, basedOn current: DragPhysicsSettings = DragPhysicsSettings()) -> DragPhysicsSettings {
        var settings = current

        switch preset {
        case .precise:
            settings.referenceDistance = 580
            settings.gamma = 1.92
            settings.inertiaStrength = 0.025
            settings.springStiffness = 210
            settings.springDamping = 29
        case .snappy:
            settings.referenceDistance = 560
            settings.gamma = 1.68
            settings.inertiaStrength = 0.075
            settings.springStiffness = 190
            settings.springDamping = 20
        case .throwable:
            settings.referenceDistance = 620
            settings.gamma = 1.48
            settings.inertiaStrength = 0.17
            settings.springStiffness = 135
            settings.springDamping = 15
        case .custom:
            break
        }

        // The original 12-second window was only a few pixels wide around the
        // low-minute snaps, so most drags never entered a haptic snap zone.
        settings.snapTolerance = 24

        return settings.sanitized
    }

    var sanitized: DragPhysicsSettings {
        var copy = self
        copy.minimumDuration = max(1, minimumDuration)
        copy.maximumDuration = max(copy.minimumDuration + 1, maximumDuration)
        copy.referenceDistance = max(80, referenceDistance)
        copy.gamma = max(0.5, gamma)
        copy.inertiaStrength = max(0, inertiaStrength)
        copy.springStiffness = max(1, springStiffness)
        copy.springDamping = max(0, springDamping)
        copy.snapTolerance = max(1, snapTolerance)
        return copy
    }
}

struct DurationMapper {
    let settings: DragPhysicsSettings

    func duration(forDistance distance: Double) -> TimeInterval {
        let clampedDistance = max(0, min(distance, settings.referenceDistance))
        let normalized = clampedDistance / settings.referenceDistance
        let shaped = pow(normalized, settings.gamma)
        let ratio = settings.maximumDuration / settings.minimumDuration
        return settings.minimumDuration * pow(ratio, shaped)
    }
}

enum SnapGrid {
    static let points: [TimeInterval] = [
        60,
        5 * 60,
        15 * 60,
        30 * 60,
        60 * 60,
        90 * 60,
        2 * 60 * 60,
        3 * 60 * 60,
        4 * 60 * 60,
        6 * 60 * 60,
        8 * 60 * 60,
        12 * 60 * 60
    ]

    static func nearest(to duration: TimeInterval, settings: DragPhysicsSettings) -> TimeInterval? {
        guard settings.snappingEnabled else { return nil }

        let eligiblePoints = points.filter { $0 >= settings.minimumDuration && $0 <= settings.maximumDuration }
        guard let point = eligiblePoints.min(by: { abs($0 - duration) < abs($1 - duration) }) else {
            return nil
        }

        let tolerance = min(max(settings.snapTolerance, point * 0.035), 120)
        return abs(point - duration) <= tolerance ? point : nil
    }
}

struct DragReleaseResult: Equatable {
    let duration: TimeInterval
    let didSnap: Bool
    let shouldHaptic: Bool
}

struct DragPhysics {
    enum Phase: Equatable {
        case idle
        case dragging
        case settling
        case finished
    }

    private let settings: DragPhysicsSettings
    private let mapper: DurationMapper

    private(set) var phase: Phase = .idle
    private(set) var displayDuration: TimeInterval
    private(set) var distance: Double = 0
    private(set) var velocity: Double = 0
    private(set) var targetDuration: TimeInterval?

    private var lastTimestamp: TimeInterval?
    private var lastDistance: Double = 0
    private var activeSnap: TimeInterval?
    private var springVelocity: Double = 0
    private var settlingElapsed: TimeInterval = 0

    init(settings: DragPhysicsSettings) {
        let sanitized = settings.sanitized
        self.settings = sanitized
        self.mapper = DurationMapper(settings: sanitized)
        self.displayDuration = sanitized.minimumDuration
    }

    mutating func begin(at timestamp: TimeInterval) {
        phase = .dragging
        displayDuration = settings.minimumDuration
        distance = 0
        velocity = 0
        lastDistance = 0
        lastTimestamp = timestamp
        activeSnap = nil
        targetDuration = nil
        springVelocity = 0
        settlingElapsed = 0
    }

    /// Stores new input only. Rendering remains owned by the display link.
    @discardableResult
    mutating func updateDrag(distance: Double, timestamp: TimeInterval) -> Bool {
        guard phase == .dragging else { return false }

        let newDistance = max(0, distance)
        if let lastTimestamp {
            let elapsed = timestamp - lastTimestamp
            if elapsed > 0.001 && elapsed < 0.25 {
                let instantaneousVelocity = (newDistance - lastDistance) / elapsed
                velocity = (velocity * 0.68) + (instantaneousVelocity * 0.32)
            }
        }

        self.distance = newDistance
        lastDistance = newDistance
        lastTimestamp = timestamp

        let rawDuration = mapper.duration(forDistance: newDistance)
        let snap = SnapGrid.nearest(to: rawDuration, settings: settings)
        let crossedIntoSnap = snap != nil && snap != activeSnap
        activeSnap = snap
        displayDuration = snap ?? rawDuration
        return crossedIntoSnap
    }

    mutating func release() -> DragReleaseResult {
        guard phase == .dragging else {
            return DragReleaseResult(
                duration: displayDuration,
                didSnap: activeSnap != nil,
                shouldHaptic: false
            )
        }

        let effectiveDistance = distance + max(0, velocity) * settings.inertiaStrength
        let projectedDuration = mapper.duration(forDistance: effectiveDistance)
        let snap = SnapGrid.nearest(to: projectedDuration, settings: settings)
        let finalDuration = snap ?? projectedDuration

        targetDuration = finalDuration
        springVelocity = 0
        settlingElapsed = 0

        if settings.reduceMotion {
            displayDuration = finalDuration
            phase = .finished
        } else {
            phase = .settling
        }

        return DragReleaseResult(
            duration: finalDuration,
            didSnap: snap != nil,
            shouldHaptic: snap != nil
        )
    }

    /// Advances the damped spring using real elapsed time from the display link.
    /// Returns true once the release animation has reached its terminal state.
    @discardableResult
    mutating func step(by elapsed: TimeInterval) -> Bool {
        guard phase == .settling, let targetDuration else {
            return phase == .finished
        }

        let boundedElapsed = min(max(elapsed, 1.0 / 240.0), 1.0 / 15.0)
        let steps = max(1, Int(ceil(boundedElapsed / (1.0 / 120.0))))
        let step = boundedElapsed / Double(steps)

        for _ in 0..<steps {
            let displacement = displayDuration - targetDuration
            let acceleration = (-settings.springStiffness * displacement) - (settings.springDamping * springVelocity)
            springVelocity += acceleration * step
            displayDuration += springVelocity * step
        }

        settlingElapsed += boundedElapsed
        if (abs(displayDuration - targetDuration) < 0.25 && abs(springVelocity) < 0.25) || settlingElapsed > 0.5 {
            displayDuration = targetDuration
            springVelocity = 0
            phase = .finished
            return true
        }

        return false
    }
}

enum DurationText {
    /// Cheap, compact formatting for the display-link path. It intentionally avoids
    /// DateComponentsFormatter, and callers update it at a throttled cadence.
    static func compact(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return String(format: "%dm %02ds", minutes, seconds)
    }
}
