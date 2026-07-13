import XCTest
@testable import DragTimer

final class TimerLifecycleTests: XCTestCase {
    @MainActor
    func testOneShotExpiryIsActionableAndMarkDoneAnnotatesHistory() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let timer = fixture.engine.createTimer(duration: 60, options: TimerOptions(label: "Tea"))
        fixture.clock.date.addTimeInterval(61)

        fixture.engine.processExpiries()

        let expiry = fixture.engine.pendingExpiries.first
        XCTAssertEqual(expiry?.timer.id, timer.id)
        XCTAssertEqual(fixture.engine.historyEntries.first?.outcome, .completed)
        XCTAssertNotNil(fixture.engine.activeAlert)

        fixture.engine.markExpiryDone(id: expiry!.id)

        XCTAssertTrue(fixture.engine.pendingExpiries.isEmpty)
        XCTAssertNil(fixture.engine.activeAlert)
        XCTAssertEqual(fixture.engine.historyEntries.first?.resolution, .markDone)
        XCTAssertTrue(fixture.engine.timers.isEmpty)
    }

    @MainActor
    func testSnoozeAndRestartCreateNewLinkedOccurrences() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let options = TimerOptions(
            label: "Focus",
            loop: true,
            snoozeMinutes: 8,
            identity: TimerIdentity(color: .violet, symbolName: "book.fill")
        )
        let original = fixture.engine.createTimer(duration: 25 * 60, options: options)
        fixture.clock.date.addTimeInterval(25 * 60 + 1)
        fixture.engine.processExpiries()
        let snoozeEvent = fixture.engine.pendingExpiries[0]

        let snoozed = fixture.engine.snoozeExpiry(id: snoozeEvent.id)

        XCTAssertNotEqual(snoozed?.id, original.id)
        XCTAssertEqual(snoozed?.resolvedOrigin, .snooze)
        XCTAssertEqual(snoozed?.parentEventID, snoozeEvent.id)
        XCTAssertEqual(snoozed?.resetDuration, 8 * 60)
        XCTAssertEqual(snoozed?.resolvedIdentity, options.identity)
        XCTAssertEqual(fixture.engine.historyEntries.first?.resolution, .snoozed)
        XCTAssertEqual(fixture.engine.historyEntries.first?.linkedTimerID, snoozed?.id)

        fixture.clock.date.addTimeInterval(8 * 60 + 1)
        fixture.engine.processExpiries()
        let restartEvent = fixture.engine.pendingExpiries[0]
        let restarted = fixture.engine.restartExpiry(id: restartEvent.id)
        XCTAssertEqual(restarted?.resolvedOrigin, .restart)
        XCTAssertEqual(restarted?.resetDuration, 8 * 60)
        XCTAssertEqual(restarted?.parentEventID, restartEvent.id)
    }

    @MainActor
    func testSimultaneousExpiriesAndStopAllRecordEveryOccurrence() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.engine.createTimer(duration: 60, options: TimerOptions(label: "One"))
        fixture.engine.createTimer(duration: 60, options: TimerOptions(label: "Two", loop: true))
        fixture.clock.date.addTimeInterval(61)

        fixture.engine.processExpiries()

        XCTAssertEqual(fixture.engine.pendingExpiries.count, 2)
        XCTAssertEqual(fixture.engine.historyEntries.filter { $0.outcome == .completed }.count, 2)
        XCTAssertTrue(fixture.engine.activeAlert?.loop == true)
        let first = fixture.engine.pendingExpiries[0]
        fixture.engine.markExpiryDone(id: first.id)
        XCTAssertEqual(fixture.engine.pendingExpiries.count, 1)

        fixture.engine.createTimer(duration: 120, options: TimerOptions(label: "Three"))
        fixture.engine.cancelAll()
        XCTAssertEqual(fixture.engine.historyEntries.filter { $0.outcome == .cancelled }.count, 1)
        XCTAssertEqual(fixture.engine.pendingExpiries.count, 1, "Stop all must not silently resolve expiry cards")
    }

    @MainActor
    func testRoutineBatchUsesOneTimestampAndKeepsIndependentLifecycle() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let templates = [
            TimerTemplate(
                duration: 5 * 60,
                options: TimerOptions(label: "Focus", notify: false),
                origin: .routine
            ),
            TimerTemplate(
                duration: 10 * 60,
                options: TimerOptions(label: "Break", loop: true),
                origin: .routine
            )
        ]

        let firstLaunch = fixture.engine.createTimers(templates: templates)
        let secondLaunch = fixture.engine.createTimers(templates: templates)

        XCTAssertEqual(firstLaunch.count, 2)
        XCTAssertEqual(Set(firstLaunch.map(\.createdAt)), [fixture.clock.date])
        XCTAssertEqual(firstLaunch.map(\.fireDate), [
            fixture.clock.date.addingTimeInterval(5 * 60),
            fixture.clock.date.addingTimeInterval(10 * 60)
        ])
        XCTAssertTrue(firstLaunch.allSatisfy { $0.resolvedOrigin == .routine })
        XCTAssertEqual(Set((firstLaunch + secondLaunch).map(\.id)).count, 4)

        fixture.engine.pause(id: firstLaunch[0].id)
        fixture.engine.cancel(id: firstLaunch[1].id)

        XCTAssertEqual(fixture.engine.timers.first { $0.id == firstLaunch[0].id }?.isPaused, true)
        XCTAssertNotNil(fixture.engine.timers.first { $0.id == secondLaunch[0].id })
        XCTAssertEqual(
            fixture.engine.historyEntries.first { $0.sourceTimerID == firstLaunch[1].id }?.origin,
            .routine
        )
    }

    @MainActor
    func testSimultaneousRoutineExpiriesKeepLoopingAudioPriority() {
        let directory = temporaryDirectory()
        let clock = TestClock(Date(timeIntervalSinceReferenceDate: 7_000))
        let audio = ControllableAudioSpy()
        let engine = TimerEngine(
            persistence: TimerPersistence(fileURL: directory.appendingPathComponent("timers.json")),
            notificationService: NotificationService(center: nil),
            audioPlayer: audio,
            now: { clock.date }
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        engine.createTimers(templates: [
            TimerTemplate(duration: 60, options: TimerOptions(label: "One shot"), origin: .routine),
            TimerTemplate(duration: 60, options: TimerOptions(label: "Looping", loop: true), origin: .routine)
        ])
        clock.date.addTimeInterval(61)
        engine.processExpiries()

        XCTAssertEqual(engine.pendingExpiries.count, 2)
        XCTAssertEqual(audio.playedLabels, ["Looping"])
        XCTAssertEqual(engine.activeAlert?.label, "Looping")
    }

    @MainActor
    func testRelaunchReconcilesPendingExpiryWithoutDuplicateHistory() {
        let directory = temporaryDirectory()
        let clock = TestClock(Date(timeIntervalSinceReferenceDate: 1_000))
        var engine: TimerEngine? = makeEngine(directory: directory, clock: clock)
        engine!.createTimer(duration: 60, options: TimerOptions(label: "Recover"))
        clock.date.addTimeInterval(61)
        engine!.processExpiries()
        let eventID = engine!.pendingExpiries[0].id
        engine!.flushPersistence()
        engine = nil

        let restored = makeEngine(directory: directory, clock: clock)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(restored.pendingExpiries.map(\.id), [eventID])
        XCTAssertEqual(restored.historyEntries.filter { $0.id == eventID }.count, 1)
        XCTAssertTrue(restored.timers.isEmpty)
        XCTAssertNil(restored.activeAlert, "Restored expiries remain actionable but silent")
    }

    @MainActor
    func testDiscardAndCancelHistoryAreDistinct() {
        let directory = temporaryDirectory()
        let clock = TestClock(Date(timeIntervalSinceReferenceDate: 3_000))
        var shouldFire = true
        var engine: TimerEngine? = TimerEngine(
            persistence: TimerPersistence(fileURL: directory.appendingPathComponent("timers.json")),
            notificationService: NotificationService(center: nil),
            audioPlayer: AudioSpy(),
            shouldFirePastDueOnWake: { shouldFire },
            now: { clock.date }
        )
        let cancelled = engine!.createTimer(duration: 120, options: TimerOptions(label: "Cancel"))
        engine!.cancel(id: cancelled.id)
        engine!.createTimer(duration: 60, options: TimerOptions(label: "Discard"))
        engine!.flushPersistence()
        engine = nil
        clock.date.addTimeInterval(61)
        shouldFire = false

        let restored = TimerEngine(
            persistence: TimerPersistence(fileURL: directory.appendingPathComponent("timers.json")),
            notificationService: NotificationService(center: nil),
            audioPlayer: AudioSpy(),
            shouldFirePastDueOnWake: { shouldFire },
            now: { clock.date }
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(restored.historyEntries.filter { $0.outcome == .cancelled }.count, 1)
        XCTAssertEqual(restored.historyEntries.filter { $0.outcome == .discarded }.count, 1)
        XCTAssertTrue(restored.pendingExpiries.isEmpty)
    }

    @MainActor
    func testNotificationActionsRecoverDiscardedPastDueTimers() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let startedAt = Date(timeIntervalSinceReferenceDate: 4_000)
        let currentDate = startedAt.addingTimeInterval(181)
        let markDone = TimerRecord(
            createdAt: startedAt,
            fireDate: startedAt.addingTimeInterval(60),
            options: TimerOptions(label: "Done")
        )
        let snooze = TimerRecord(
            createdAt: startedAt,
            fireDate: startedAt.addingTimeInterval(120),
            options: TimerOptions(label: "Snooze", snoozeMinutes: 7)
        )
        let restart = TimerRecord(
            createdAt: startedAt,
            fireDate: startedAt.addingTimeInterval(180),
            options: TimerOptions(label: "Restart")
        )
        let persistence = TimerPersistence(fileURL: directory.appendingPathComponent("timers.json"))
        try persistence.save([markDone, snooze, restart])
        let engine = TimerEngine(
            persistence: persistence,
            notificationService: NotificationService(center: nil),
            audioPlayer: AudioSpy(),
            shouldFirePastDueOnWake: { false },
            now: { currentDate }
        )
        XCTAssertEqual(engine.historyEntries.filter { $0.outcome == .discarded }.count, 3)
        XCTAssertTrue(engine.pendingExpiries.isEmpty)

        engine.handleNotificationAction(timerID: markDone.id, action: .markDone)
        engine.handleNotificationAction(timerID: snooze.id, action: .snooze)
        engine.handleNotificationAction(timerID: restart.id, action: .restart)

        let doneHistory = engine.historyEntries.first { $0.sourceTimerID == markDone.id }
        let snoozeHistory = engine.historyEntries.first { $0.sourceTimerID == snooze.id }
        let restartHistory = engine.historyEntries.first { $0.sourceTimerID == restart.id }
        XCTAssertEqual(doneHistory?.outcome, .completed)
        XCTAssertEqual(doneHistory?.resolution, .markDone)
        XCTAssertEqual(snoozeHistory?.outcome, .completed)
        XCTAssertEqual(snoozeHistory?.resolution, .snoozed)
        XCTAssertEqual(restartHistory?.outcome, .completed)
        XCTAssertEqual(restartHistory?.resolution, .restarted)
        XCTAssertEqual(engine.timers.first { $0.parentEventID == snoozeHistory?.id }?.resetDuration, 7 * 60)
        XCTAssertEqual(engine.timers.first { $0.parentEventID == restartHistory?.id }?.resetDuration, 180)
        XCTAssertTrue(engine.pendingExpiries.isEmpty)
    }

    @MainActor
    func testFinishedOneShotDoesNotSuppressLaterExpiryAudio() {
        let directory = temporaryDirectory()
        let clock = TestClock(Date(timeIntervalSinceReferenceDate: 5_000))
        let audio = ControllableAudioSpy()
        let engine = TimerEngine(
            persistence: TimerPersistence(fileURL: directory.appendingPathComponent("timers.json")),
            notificationService: NotificationService(center: nil),
            audioPlayer: audio,
            now: { clock.date }
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        engine.createTimer(duration: 60, options: TimerOptions(label: "First"))
        clock.date.addTimeInterval(61)
        engine.processExpiries()
        XCTAssertEqual(audio.playedLabels, ["First"])
        audio.finish()

        engine.createTimer(duration: 60, options: TimerOptions(label: "Second"))
        clock.date.addTimeInterval(61)
        engine.processExpiries()

        XCTAssertEqual(audio.playedLabels, ["First", "Second"])
    }

    @MainActor
    func testRelaunchCompletesPartiallyPersistedSnoozeWithoutCreatingDuplicateChild() throws {
        let directory = temporaryDirectory()
        let now = Date(timeIntervalSinceReferenceDate: 8_000)
        let original = TimerRecord(
            createdAt: now.addingTimeInterval(-60),
            fireDate: now,
            options: TimerOptions(label: "Recover snooze", snoozeMinutes: 5)
        )
        let expiry = PendingExpiry(timer: original, expiredAt: now)
        let unresolved = TimerHistoryEntry(
            id: expiry.id,
            timer: original,
            endedAt: now,
            outcome: .completed
        )
        let child = TimerRecord(
            createdAt: now,
            fireDate: now.addingTimeInterval(300),
            options: original.options,
            origin: .snooze,
            parentEventID: expiry.id
        )
        try TimerPersistence(fileURL: directory.appendingPathComponent("timers.json")).save([child])
        try PendingExpiryStore(fileURL: directory.appendingPathComponent("pending-expiries.json")).save([expiry])
        try TimerHistoryStore(fileURL: directory.appendingPathComponent("history.json")).save([unresolved], now: now)

        let engine = TimerEngine(
            persistence: TimerPersistence(fileURL: directory.appendingPathComponent("timers.json")),
            notificationService: NotificationService(center: nil),
            audioPlayer: AudioSpy(),
            now: { now }
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertTrue(engine.pendingExpiries.isEmpty)
        XCTAssertEqual(engine.timers.map(\.id), [child.id])
        XCTAssertEqual(engine.historyEntries.first?.resolution, .snoozed)
        XCTAssertEqual(engine.historyEntries.first?.linkedTimerID, child.id)
    }

    @MainActor
    private func makeFixture() -> Fixture {
        let directory = temporaryDirectory()
        let clock = TestClock(Date(timeIntervalSinceReferenceDate: 10_000))
        return Fixture(
            engine: makeEngine(directory: directory, clock: clock),
            clock: clock,
            cleanup: { try? FileManager.default.removeItem(at: directory) }
        )
    }

    @MainActor
    private func makeEngine(directory: URL, clock: TestClock) -> TimerEngine {
        TimerEngine(
            persistence: TimerPersistence(fileURL: directory.appendingPathComponent("timers.json")),
            notificationService: NotificationService(center: nil),
            audioPlayer: AudioSpy(),
            now: { clock.date }
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DragTimerLifecycleTests-\(UUID().uuidString)", isDirectory: true)
    }

    private struct Fixture {
        let engine: TimerEngine
        let clock: TestClock
        let cleanup: () -> Void
    }

    private final class TestClock {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    private final class AudioSpy: AudioAlertPlaying {
        func play(timer: TimerRecord) {}
        func stop() {}
    }

    private final class ControllableAudioSpy: AudioAlertPlaying {
        var playedLabels: [String] = []
        var finished: (() -> Void)?
        func play(timer: TimerRecord) { playedLabels.append(timer.label) }
        func stop() {}
        func setPlaybackFinishedHandler(_ handler: @escaping () -> Void) { finished = handler }
        func finish() { finished?() }
    }
}
