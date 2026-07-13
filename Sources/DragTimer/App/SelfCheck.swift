import Foundation

/// Lightweight deterministic checks that work with Command Line Tools as well
/// as full Xcode. They deliberately exercise only pure model code, never UI.
enum SelfCheck {
    private enum Failure: Error, CustomStringConvertible {
        case assertion(String)

        var description: String {
            switch self {
            case let .assertion(message): return message
            }
        }
    }

    static func run() -> Int32 {
        do {
            try verifyDistanceMapping()
            try verifyInertiaProjection()
            try verifySpringSettlement()
            try verifyDeadlineHeap()
            try verifyPersistenceRoundTrip()
            try verifyTimerDefaultsPersistence()
            try verifyTimerLifecycle()
            try verifyLoopingAlertPriority()
            print("DragTimer self-check passed")
            return 0
        } catch {
            fputs("DragTimer self-check failed: \(error)\n", stderr)
            return 1
        }
    }

    private static func verifyDistanceMapping() throws {
        var settings = DragPhysicsSettings()
        settings.minimumDuration = 60
        settings.maximumDuration = 14_400
        settings.referenceDistance = 600
        let mapper = DurationMapper(settings: settings)

        try require(abs(mapper.duration(forDistance: 0) - 60) < 0.001, "minimum duration mapping")
        try require(abs(mapper.duration(forDistance: 600) - 14_400) < 0.001, "maximum duration mapping")
        try require(SnapGrid.nearest(to: 305, settings: settings) == 300, "five-minute snap")
    }

    private static func verifyInertiaProjection() throws {
        var settings = DragPhysicsSettings.forPreset(.throwable)
        settings.snappingEnabled = false
        settings.reduceMotion = true
        let mapper = DurationMapper(settings: settings)
        var physics = DragPhysics(settings: settings)

        physics.begin(at: 1)
        _ = physics.updateDrag(distance: 250, timestamp: 1.1)
        let release = physics.release()

        try require(release.duration > mapper.duration(forDistance: 250), "velocity should project release forward")
        try require(physics.phase == .finished, "reduced-motion release should finish immediately")
    }

    private static func verifySpringSettlement() throws {
        var settings = DragPhysicsSettings.forPreset(.snappy)
        settings.snappingEnabled = false
        var physics = DragPhysics(settings: settings)

        physics.begin(at: 1)
        _ = physics.updateDrag(distance: 320, timestamp: 1.12)
        let release = physics.release()

        var completed = false
        for _ in 0..<180 where !completed {
            completed = physics.step(by: 1.0 / 120.0)
        }

        try require(completed, "spring should settle in bounded time")
        try require(abs(physics.displayDuration - release.duration) < 0.25, "spring should settle at release target")
    }

    private static func verifyDeadlineHeap() throws {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let options = TimerOptions(label: "Check")
        let first = TimerRecord(fireDate: start.addingTimeInterval(10), options: options)
        let second = TimerRecord(fireDate: start.addingTimeInterval(20), options: options)
        let third = TimerRecord(fireDate: start.addingTimeInterval(30), options: options)
        var heap = DeadlineHeap()

        heap.insert(third)
        heap.insert(first)
        heap.insert(second)
        try require(heap.pop()?.id == first.id, "heap first deadline")
        try require(heap.pop()?.id == second.id, "heap second deadline")
        try require(heap.pop()?.id == third.id, "heap third deadline")
    }

    private static func verifyPersistenceRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DragTimerSelfCheck-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let options = TimerOptions(label: "Persisted timer")
        let record = TimerRecord(fireDate: Date().addingTimeInterval(300), options: options)
        let persistence = TimerPersistence(fileURL: directory.appendingPathComponent("timers.json"))
        try persistence.save([record])
        let restored = try persistence.load()

        try require(restored == [record], "timer persistence round trip")
    }

    private static func verifyTimerDefaultsPersistence() throws {
        let suiteName = "DragTimerSelfCheck-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw Failure.assertion("settings test defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.defaultLabel = "Tea"
        settings.defaultSoundName = AlertSound.systemBeep.rawValue
        settings.defaultVolume = 0.35
        settings.defaultLoop = true
        settings.defaultNotificationsEnabled = false
        settings.defaultSnoozeMinutes = 12
        settings.askForLabelAfterDrag = false
        settings.setQuickStartMinutes([30, 5, 30, 120])

        let restored = AppSettings(defaults: defaults)
        let options = restored.defaultOptions()
        try require(options.label == "Tea", "default timer label persists")
        try require(options.soundName == AlertSound.systemBeep.rawValue, "default sound persists")
        try require(abs(options.volume - 0.35) < 0.001, "default volume persists")
        try require(options.loop, "default loop persists")
        try require(!options.notify, "default notification preference persists")
        try require(options.snoozeMinutes == 12, "default snooze persists")
        try require(!restored.askForLabelAfterDrag, "drag label prompt preference persists")
        try require(restored.quickStartMinutes == [5, 30, 120], "quick start presets persist and normalize")
        try require(
            TimerOptions(label: "Legacy", soundName: "Pulse").soundName == AlertSound.glass.rawValue,
            "legacy Pulse sound normalizes to Glass"
        )
    }

    private static func verifyTimerLifecycle() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DragTimerSelfCheck-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = TimerPersistence(fileURL: directory.appendingPathComponent("timers.json"))
        let engine = TimerEngine(
            persistence: persistence,
            notificationService: NotificationService(center: nil),
            audioPlayer: RecordingAudioPlayer()
        )
        let timer = engine.createTimer(duration: 120, options: TimerOptions(label: "Lifecycle"))

        engine.pause(id: timer.id)
        guard let paused = engine.timers.first else {
            throw Failure.assertion("paused timer remains visible")
        }
        try require(paused.isPaused, "timer pauses")
        try require((119...120).contains(Int(paused.remaining().rounded())), "pause keeps remaining duration")
        let savedPausedTimers = try persistence.load()
        try require(savedPausedTimers.first?.isPaused == true, "paused state persists")

        engine.resume(id: timer.id)
        try require(engine.timers.first?.isPaused == false, "timer resumes")

        engine.reset(id: timer.id)
        let resetRemaining = engine.timers.first?.remaining() ?? 0
        try require(resetRemaining > 119 && resetRemaining <= 120, "running timer resets to its original duration")

        engine.pause(id: timer.id)
        engine.reset(id: timer.id)
        try require(engine.timers.first?.remaining() == 120, "paused timer resets without resuming")

        engine.cancelAll()
        try require(engine.timers.isEmpty, "stop all clears timers")
        let savedClearedTimers = try persistence.load()
        try require(savedClearedTimers.isEmpty, "stop all persists the cleared state")
    }

    private static func verifyLoopingAlertPriority() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DragTimerSelfCheck-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = TimerPersistence(fileURL: directory.appendingPathComponent("timers.json"))
        let past = Date().addingTimeInterval(-1)
        let looping = TimerRecord(
            fireDate: past,
            options: TimerOptions(label: "Looping", loop: true)
        )
        let oneShot = TimerRecord(
            fireDate: past,
            options: TimerOptions(label: "One shot", loop: false)
        )
        try persistence.save([looping, oneShot])

        let audio = RecordingAudioPlayer()
        let engine = TimerEngine(
            persistence: persistence,
            notificationService: NotificationService(center: nil),
            audioPlayer: audio,
            shouldFirePastDueOnWake: { true }
        )

        try require(audio.playedTimers.map(\.id) == [looping.id], "looping timer keeps audio priority")
        try require(engine.activeAlert?.id == looping.id, "looping timer remains stoppable")
    }

    private final class RecordingAudioPlayer: AudioAlertPlaying {
        private(set) var playedTimers: [TimerRecord] = []

        func play(timer: TimerRecord) {
            playedTimers.append(timer)
        }

        func stop() {}
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure.assertion(message) }
    }
}
