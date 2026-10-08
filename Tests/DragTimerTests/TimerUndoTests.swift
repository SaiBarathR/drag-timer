import XCTest
@testable import DragTimer

final class TimerUndoTests: XCTestCase {
    @MainActor
    func testUndoPutsACancelledTimerBackWithTheEndItHad() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let timer = fixture.engine.createTimer(duration: 600, options: TimerOptions(label: "Tea"))
        fixture.clock.date.addTimeInterval(100)

        fixture.engine.cancel(id: timer.id)
        XCTAssertTrue(fixture.engine.timers.isEmpty)
        XCTAssertEqual(fixture.engine.undoableRemoval?.kind, .cancelled)
        XCTAssertEqual(fixture.engine.undoableRemoval?.summary, "Cancelled Tea")
        XCTAssertEqual(fixture.engine.historyEntries.map(\.outcome), [.cancelled])

        fixture.clock.date.addTimeInterval(4)
        fixture.engine.undoLastRemoval()

        XCTAssertEqual(fixture.engine.timers, [timer])
        XCTAssertTrue(fixture.engine.historyEntries.isEmpty)
        XCTAssertNil(fixture.engine.undoableRemoval)

        // It is scheduled again, at the original end and not a later one.
        fixture.clock.date = timer.fireDate.addingTimeInterval(-1)
        fixture.engine.processExpiries()
        XCTAssertTrue(fixture.engine.pendingExpiries.isEmpty)
        fixture.clock.date = timer.fireDate
        fixture.engine.processExpiries()
        XCTAssertEqual(fixture.engine.pendingExpiries.map(\.timer.id), [timer.id])
    }

    @MainActor
    func testUndoTakesBackMarkDone() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let timer = fixture.engine.createTimer(duration: 600, options: TimerOptions(label: "Laundry"))

        fixture.engine.markDone(id: timer.id)
        XCTAssertEqual(fixture.engine.undoableRemoval?.summary, "Marked Laundry done")
        XCTAssertEqual(fixture.engine.historyEntries.map(\.resolution), [.markDone])

        fixture.engine.undoLastRemoval()

        XCTAssertEqual(fixture.engine.timers.map(\.id), [timer.id])
        XCTAssertTrue(fixture.engine.historyEntries.isEmpty)
    }

    @MainActor
    func testUndoRestoresEverythingStopAllTookIncludingAPause() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let running = fixture.engine.createTimer(duration: 300, options: TimerOptions(label: "Running"))
        let paused = fixture.engine.createTimer(duration: 900, options: TimerOptions(label: "Paused"))
        fixture.clock.date.addTimeInterval(60)
        fixture.engine.pause(id: paused.id)
        let before = fixture.engine.timers

        fixture.engine.cancelAll()
        XCTAssertEqual(fixture.engine.undoableRemoval?.summary, "Stopped 2 timers")
        XCTAssertEqual(fixture.engine.historyEntries.count, 2)

        fixture.engine.undoLastRemoval()

        XCTAssertEqual(fixture.engine.timers, before)
        XCTAssertEqual(fixture.engine.timers.first { $0.id == paused.id }?.pausedRemaining, 840)
        XCTAssertTrue(fixture.engine.historyEntries.isEmpty)

        // Only the running one is scheduled; the paused one does not fire.
        fixture.clock.date.addTimeInterval(3_600)
        fixture.engine.processExpiries()
        XCTAssertEqual(fixture.engine.pendingExpiries.map(\.timer.id), [running.id])
        XCTAssertEqual(fixture.engine.timers.map(\.id), [paused.id])
    }

    @MainActor
    func testOnlyTheLastRemovalCanBeUndone() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let first = fixture.engine.createTimer(duration: 300, options: TimerOptions(label: "First"))
        let second = fixture.engine.createTimer(duration: 600, options: TimerOptions(label: "Second"))

        fixture.engine.cancel(id: first.id)
        fixture.engine.cancel(id: second.id)
        fixture.engine.undoLastRemoval()
        fixture.engine.undoLastRemoval()

        XCTAssertEqual(fixture.engine.timers.map(\.id), [second.id])
        XCTAssertEqual(fixture.engine.historyEntries.map(\.sourceTimerID), [first.id])
    }

    @MainActor
    func testUndoIsRefusedOnceTheWindowHasPassed() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let timer = fixture.engine.createTimer(duration: 600, options: TimerOptions(label: "Late"))

        fixture.engine.cancel(id: timer.id)
        fixture.clock.date.addTimeInterval(TimerEngine.undoWindow + 1)
        XCTAssertNotNil(fixture.engine.undoableRemoval, "Still on screen, as after a sleep")
        fixture.engine.undoLastRemoval()

        XCTAssertTrue(fixture.engine.timers.isEmpty)
        XCTAssertEqual(fixture.engine.historyEntries.map(\.outcome), [.cancelled])
        XCTAssertNil(fixture.engine.undoableRemoval, "A dead offer must not stay on screen")
    }

    @MainActor
    func testStartingARemovedTimerAgainFromHistoryAnswersTheOffer() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let tea = fixture.engine.createTimer(duration: 600, options: TimerOptions(label: "Tea"))
        let other = fixture.engine.createTimer(duration: 900, options: TimerOptions(label: "Other"))
        fixture.engine.cancel(id: other.id)
        fixture.engine.cancel(id: tea.id)
        let teaEntry = fixture.engine.historyEntries.first { $0.sourceTimerID == tea.id }!

        // An older entry does not concern the offer.
        fixture.engine.restartHistoryEntry(id: fixture.engine.historyEntries.first { $0.sourceTimerID == other.id }!.id)
        XCTAssertNotNil(fixture.engine.undoableRemoval)

        let again = fixture.engine.restartHistoryEntry(id: teaEntry.id)
        XCTAssertNil(fixture.engine.undoableRemoval)
        fixture.engine.undoLastRemoval()

        XCTAssertEqual(fixture.engine.timers.filter { $0.label == "Tea" }.map(\.id), [again?.id])
        XCTAssertTrue(fixture.engine.historyEntries.contains { $0.id == teaEntry.id })
    }

    @MainActor
    func testStartingOneTimerOfAStopAllAgainLeavesTheRestOnOffer() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let tea = fixture.engine.createTimer(duration: 600, options: TimerOptions(label: "Tea"))
        let coffee = fixture.engine.createTimer(duration: 900, options: TimerOptions(label: "Coffee"))
        fixture.clock.date.addTimeInterval(120)
        fixture.engine.pause(id: coffee.id)
        fixture.engine.cancelAll()
        let offer = fixture.engine.undoableRemoval
        let teaEntry = fixture.engine.historyEntries.first { $0.sourceTimerID == tea.id }!

        let again = fixture.engine.restartHistoryEntry(id: teaEntry.id)

        XCTAssertEqual(fixture.engine.undoableRemoval?.id, offer?.id)
        XCTAssertEqual(fixture.engine.undoableRemoval?.timers.map(\.id), [coffee.id])
        XCTAssertEqual(fixture.engine.undoableRemoval?.summary, "Stopped 1 timer")

        fixture.engine.undoLastRemoval()

        XCTAssertEqual(Set(fixture.engine.timers.map(\.id)), [again!.id, coffee.id])
        XCTAssertEqual(fixture.engine.timers.first { $0.id == coffee.id }?.pausedRemaining, 780)
        XCTAssertEqual(fixture.engine.historyEntries.map(\.id), [teaEntry.id])
    }

    @MainActor
    func testATimerWhoseEndPassedWhileItWasRemovedRingsAtOnce() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let timer = fixture.engine.createTimer(duration: 60, options: TimerOptions(label: "Nearly"))
        fixture.clock.date.addTimeInterval(57)

        fixture.engine.cancel(id: timer.id)
        fixture.clock.date.addTimeInterval(5)
        fixture.engine.undoLastRemoval()
        fixture.engine.processExpiries()

        XCTAssertTrue(fixture.engine.timers.isEmpty)
        XCTAssertEqual(fixture.engine.pendingExpiries.map(\.timer.id), [timer.id])
        XCTAssertEqual(fixture.engine.historyEntries.map(\.outcome), [.completed])
    }

    @MainActor
    func testDiscardingAJustDraggedTimerIsNotOfferedBack() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let timer = fixture.engine.createTimer(duration: 300, options: TimerOptions(label: "Timer"))

        fixture.engine.discard(id: timer.id)

        XCTAssertNil(fixture.engine.undoableRemoval)
    }

    @MainActor
    func testStopAllWithNothingRunningOffersNothing() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        fixture.engine.cancelAll()

        XCTAssertNil(fixture.engine.undoableRemoval)
    }

    @MainActor
    func testAnUndoneRemovalIsWhatTheNextLaunchFinds() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DragTimerUndoTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestClock(Date(timeIntervalSinceReferenceDate: 10_000))
        let engine = makeEngine(directory: directory, clock: clock)
        let kept = engine.createTimer(duration: 600, options: TimerOptions(label: "Kept"))
        let paused = engine.createTimer(duration: 900, options: TimerOptions(label: "Paused"))
        engine.pause(id: paused.id)

        engine.cancelAll()
        XCTAssertTrue(makeEngine(directory: directory, clock: clock).timers.isEmpty)
        engine.undoLastRemoval()

        // Nothing else is written between the undo and this launch.
        let relaunched = makeEngine(directory: directory, clock: clock)
        XCTAssertEqual(Set(relaunched.timers.map(\.id)), [kept.id, paused.id])
        XCTAssertEqual(relaunched.timers.first { $0.id == paused.id }?.pausedRemaining, 900)
        XCTAssertTrue(relaunched.historyEntries.isEmpty)
        XCTAssertNil(relaunched.undoableRemoval)
    }

    /// Undo writes the timers before it writes history. If the app dies in
    /// between, the next launch finds the timers and their "cancelled"
    /// entries, treats the timers as ended, and the removal simply stands.
    @MainActor
    func testACrashHalfwayThroughAnUndoLeavesTheRemovalStanding() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DragTimerUndoTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestClock(Date(timeIntervalSinceReferenceDate: 10_000))
        let engine = makeEngine(directory: directory, clock: clock)
        let tea = engine.createTimer(duration: 600, options: TimerOptions(label: "Tea"))
        engine.cancel(id: tea.id)
        let historyURL = directory.appendingPathComponent("history.json")
        let historyBeforeUndo = try Data(contentsOf: historyURL)

        engine.undoLastRemoval()
        // The first write happened: the timer is back in its file.
        let written = try JSONDecoder().decode(
            [TimerRecord].self,
            from: Data(contentsOf: directory.appendingPathComponent("timers.json"))
        )
        XCTAssertEqual(written.map(\.id), [tea.id])
        // The second write never happened.
        try historyBeforeUndo.write(to: historyURL)

        let relaunched = makeEngine(directory: directory, clock: clock)
        XCTAssertTrue(relaunched.timers.isEmpty)
        XCTAssertEqual(relaunched.historyEntries.map(\.sourceTimerID), [tea.id])
        XCTAssertEqual(relaunched.historyEntries.map(\.outcome), [.cancelled])
    }

    /// With the engine's own clock and scheduler: a restored timer is armed
    /// again without anyone asking the engine to look.
    @MainActor
    func testAnUndoneTimerFiresOnTheRealClock() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DragTimerUndoTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = TimerEngine(
            persistence: TimerPersistence(fileURL: directory.appendingPathComponent("timers.json")),
            notificationService: NotificationService(center: nil),
            audioPlayer: SilentAudio()
        )
        let timer = engine.createTimer(duration: 1, options: TimerOptions(label: "Real"))
        engine.cancel(id: timer.id)

        engine.undoLastRemoval()

        let limit = Date().addingTimeInterval(10)
        while engine.pendingExpiries.isEmpty, Date() < limit {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(engine.pendingExpiries.map(\.timer.id), [timer.id])
        XCTAssertEqual(engine.historyEntries.map(\.outcome), [.completed])
    }

    @MainActor
    private func makeFixture() -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DragTimerUndoTests-\(UUID().uuidString)", isDirectory: true)
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
            audioPlayer: SilentAudio(),
            now: { clock.date }
        )
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

    private final class SilentAudio: AudioAlertPlaying {
        func play(timer: TimerRecord) {}
        func stop() {}
    }
}
