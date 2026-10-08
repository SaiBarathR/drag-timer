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
    func testAddTimeExtendsRunningTimerAndKeepsItsPlannedDuration() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let timer = fixture.engine.createTimer(
            duration: 3_600,
            options: TimerOptions(label: "Focus", snoozeMinutes: 5)
        )
        fixture.clock.date.addTimeInterval(1_200)

        fixture.engine.addTime(id: timer.id)

        let extended = fixture.engine.timers.first
        XCTAssertEqual(extended?.remaining(at: fixture.clock.date), 2_700)
        XCTAssertEqual(extended?.resetDuration, 3_600)
        fixture.clock.date.addTimeInterval(2_699)
        fixture.engine.processExpiries()
        XCTAssertTrue(fixture.engine.pendingExpiries.isEmpty)
        fixture.clock.date.addTimeInterval(1)
        fixture.engine.processExpiries()
        XCTAssertEqual(fixture.engine.pendingExpiries.first?.timer.id, timer.id)
    }

    @MainActor
    func testAddTimeKeepsPausedTimerPaused() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let timer = fixture.engine.createTimer(
            duration: 600,
            options: TimerOptions(label: "Tea", snoozeMinutes: 2)
        )
        fixture.engine.pause(id: timer.id)

        fixture.engine.addTime(id: timer.id)

        XCTAssertEqual(fixture.engine.timers.first?.isPaused, true)
        XCTAssertEqual(fixture.engine.timers.first?.pausedRemaining, 720)
    }

    @MainActor
    func testAdjustTimeMovesTheEndBothWaysAndKeepsThePlannedDuration() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let timer = fixture.engine.createTimer(duration: 600, options: TimerOptions(label: "Focus"))
        fixture.clock.date.addTimeInterval(100)

        fixture.engine.adjustTime(id: timer.id, by: 60)
        XCTAssertEqual(fixture.engine.timers.first?.remaining(at: fixture.clock.date), 560)
        fixture.engine.adjustTime(id: timer.id, by: -60)
        fixture.engine.adjustTime(id: timer.id, by: -60)
        XCTAssertEqual(fixture.engine.timers.first?.remaining(at: fixture.clock.date), 440)
        XCTAssertEqual(fixture.engine.timers.first?.resetDuration, 600)

        fixture.clock.date.addTimeInterval(439)
        fixture.engine.processExpiries()
        XCTAssertTrue(fixture.engine.pendingExpiries.isEmpty)
        fixture.clock.date.addTimeInterval(1)
        fixture.engine.processExpiries()
        XCTAssertEqual(fixture.engine.pendingExpiries.first?.timer.id, timer.id)
    }

    @MainActor
    func testAdjustTimeNeverEndsATimerAndKeepsAPausedTimerPaused() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let short = fixture.engine.createTimer(duration: 60, options: TimerOptions(label: "Short"))
        let paused = fixture.engine.createTimer(duration: 300, options: TimerOptions(label: "Paused"))
        fixture.engine.pause(id: paused.id)

        fixture.engine.adjustTime(id: short.id, by: -60)
        fixture.engine.adjustTime(id: paused.id, by: -60)
        fixture.engine.adjustTime(id: paused.id, by: -300)

        let timers = fixture.engine.timers
        XCTAssertEqual(timers.first { $0.id == short.id }?.remaining(at: fixture.clock.date), 60)
        XCTAssertEqual(timers.first { $0.id == paused.id }?.pausedRemaining, 240)
        XCTAssertTrue(fixture.engine.historyEntries.isEmpty)
    }

    @MainActor
    func testSetRemainingRestartsTheCountdownAtANewPlannedLength() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let timer = fixture.engine.createTimer(duration: 1_800, options: TimerOptions(label: "Meant twenty"))
        fixture.clock.date.addTimeInterval(300)

        fixture.engine.setRemaining(id: timer.id, to: 1_200)

        let retimed = fixture.engine.timers.first
        XCTAssertEqual(retimed?.remaining(at: fixture.clock.date), 1_200)
        XCTAssertEqual(retimed?.resetDuration, 1_200)
        XCTAssertEqual(retimed?.progress(at: fixture.clock.date), 0)
        XCTAssertEqual(retimed?.label, "Meant twenty")

        fixture.clock.date.addTimeInterval(600)
        fixture.engine.reset(id: timer.id)
        XCTAssertEqual(fixture.engine.timers.first?.remaining(at: fixture.clock.date), 1_200)

        fixture.clock.date.addTimeInterval(1_200)
        fixture.engine.processExpiries()
        XCTAssertEqual(fixture.engine.historyEntries.first?.plannedDuration, 1_200)
    }

    @MainActor
    func testSetRemainingKeepsAPausedTimerPausedAndStaysWithinADay() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let timer = fixture.engine.createTimer(duration: 600, options: TimerOptions(label: "Paused"))
        fixture.engine.pause(id: timer.id)

        fixture.engine.setRemaining(id: timer.id, to: 90)
        XCTAssertEqual(fixture.engine.timers.first?.pausedRemaining, 90)
        XCTAssertEqual(fixture.engine.timers.first?.resetDuration, 90)

        fixture.engine.setRemaining(id: timer.id, to: 100 * 3_600)
        XCTAssertEqual(fixture.engine.timers.first?.pausedRemaining, 24 * 3_600)
        fixture.engine.setRemaining(id: UUID(), to: 60)
        XCTAssertEqual(fixture.engine.timers.count, 1)
    }

    @MainActor
    func testRenameAndDiscardActOnTheRunningTimerWithoutHistory() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let timer = fixture.engine.createTimer(duration: 300, options: TimerOptions(label: "Timer"))
        fixture.clock.date.addTimeInterval(20)

        fixture.engine.rename(id: timer.id, to: "Tea")

        XCTAssertEqual(fixture.engine.timers.first?.label, "Tea")
        XCTAssertEqual(fixture.engine.timers.first?.resetDuration, 300)
        XCTAssertEqual(fixture.engine.timers.first?.fireDate, timer.fireDate)

        fixture.engine.discard(id: timer.id)

        XCTAssertTrue(fixture.engine.timers.isEmpty)
        XCTAssertTrue(fixture.engine.historyEntries.isEmpty)
    }

    @MainActor
    func testRenameReachesATimerThatExpiredMeanwhile() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let timer = fixture.engine.createTimer(duration: 60, options: TimerOptions(label: "Timer"))
        fixture.clock.date.addTimeInterval(61)
        fixture.engine.processExpiries()

        fixture.engine.rename(id: timer.id, to: "Tea")

        let expiry = fixture.engine.pendingExpiries.first
        XCTAssertEqual(expiry?.timer.label, "Tea")
        XCTAssertEqual(fixture.engine.historyEntries.first?.label, "Tea")
        XCTAssertEqual(fixture.engine.restartExpiry(id: expiry!.id)?.label, "Tea")
    }

    @MainActor
    func testDiscardDismissesATimerThatExpiredMeanwhile() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let timer = fixture.engine.createTimer(
            duration: 60,
            options: TimerOptions(label: "Timer", loop: true)
        )
        fixture.clock.date.addTimeInterval(61)
        fixture.engine.processExpiries()
        XCTAssertNotNil(fixture.engine.activeAlert)

        fixture.engine.discard(id: timer.id)

        XCTAssertTrue(fixture.engine.pendingExpiries.isEmpty)
        XCTAssertNil(fixture.engine.activeAlert)
        XCTAssertTrue(fixture.engine.timers.isEmpty)
    }

    @MainActor
    func testResetReturnsRunningAndPausedTimersToTheirPlannedDuration() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let timer = fixture.engine.createTimer(duration: 120, options: TimerOptions(label: "Reset"))
        fixture.clock.date.addTimeInterval(45)

        fixture.engine.reset(id: timer.id)

        XCTAssertEqual(fixture.engine.timers.first?.remaining(at: fixture.clock.date), 120)
        XCTAssertEqual(fixture.engine.timers.first?.isPaused, false)

        fixture.clock.date.addTimeInterval(30)
        fixture.engine.pause(id: timer.id)
        XCTAssertEqual(fixture.engine.timers.first?.pausedRemaining, 90)

        fixture.engine.reset(id: timer.id)

        XCTAssertEqual(fixture.engine.timers.first?.pausedRemaining, 120)
        fixture.engine.resume(id: timer.id)
        XCTAssertEqual(fixture.engine.timers.first?.remaining(at: fixture.clock.date), 120)
    }

    /// Every other test advances a fake clock and calls `processExpiries`
    /// itself; this one lets the real scheduler fire.
    @MainActor
    func testSchedulerFiresATimerOnTheRealClock() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = TimerEngine(
            persistence: TimerPersistence(fileURL: directory.appendingPathComponent("timers.json")),
            notificationService: NotificationService(center: nil),
            audioPlayer: AudioSpy()
        )
        let timer = engine.createTimer(duration: 1, options: TimerOptions(label: "Real"))

        // Polled with a generous limit rather than fixed windows, so a slow
        // CI runner delays the test instead of failing it.
        let limit = Date().addingTimeInterval(10)
        while engine.pendingExpiries.isEmpty, Date() < limit {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        XCTAssertEqual(engine.pendingExpiries.map(\.timer.id), [timer.id])
        XCTAssertGreaterThanOrEqual(engine.pendingExpiries.first?.expiredAt ?? .distantPast, timer.fireDate)
    }

    @MainActor
    func testRenameFollowsASnoozeMadeWhileTheNamePromptWasOpen() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let timer = fixture.engine.createTimer(duration: 60, options: TimerOptions(label: "Timer"))
        fixture.clock.date.addTimeInterval(61)
        fixture.engine.processExpiries()
        let child = fixture.engine.snoozeExpiry(id: fixture.engine.pendingExpiries[0].id)

        fixture.engine.rename(id: timer.id, to: "Tea")

        XCTAssertEqual(fixture.engine.timers.map(\.id), [child?.id])
        XCTAssertEqual(fixture.engine.timers.first?.label, "Tea")
        XCTAssertEqual(fixture.engine.historyEntries.map(\.label), ["Tea"])
        XCTAssertEqual(fixture.engine.historyEntries.first?.optionsSnapshot.label, "Tea")
    }

    @MainActor
    func testDiscardFollowsARestartMadeWhileTheNamePromptWasOpen() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let timer = fixture.engine.createTimer(duration: 60, options: TimerOptions(label: "Timer"))
        let bystander = fixture.engine.createTimer(duration: 600, options: TimerOptions(label: "Other"))
        fixture.clock.date.addTimeInterval(61)
        fixture.engine.processExpiries()
        fixture.engine.restartExpiry(id: fixture.engine.pendingExpiries[0].id)
        XCTAssertEqual(fixture.engine.timers.count, 2)

        fixture.engine.discard(id: timer.id)

        XCTAssertEqual(fixture.engine.timers.map(\.id), [bystander.id])
    }

    @MainActor
    func testNewTimerLabelsAreTrimmedLikeEditedOnes() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        let timer = fixture.engine.createTimer(duration: 60, options: TimerOptions(label: "  Tea \n"))

        XCTAssertEqual(timer.label, "Tea")
    }

    @MainActor
    func testMarkDoneCompletesRunningTimerWithoutAlertOrExpiryCard() {
        let directory = temporaryDirectory()
        let clock = TestClock(Date(timeIntervalSinceReferenceDate: 11_000))
        let audio = ControllableAudioSpy()
        let engine = TimerEngine(
            persistence: TimerPersistence(fileURL: directory.appendingPathComponent("timers.json")),
            notificationService: NotificationService(center: nil),
            audioPlayer: audio,
            now: { clock.date }
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let done = engine.createTimer(duration: 25 * 60, options: TimerOptions(label: "Focus"))
        let other = engine.createTimer(duration: 60, options: TimerOptions(label: "Tea"))
        clock.date.addTimeInterval(10 * 60)

        engine.markDone(id: done.id)

        XCTAssertEqual(engine.timers.map(\.id), [other.id])
        XCTAssertTrue(engine.pendingExpiries.isEmpty)
        XCTAssertNil(engine.activeAlert)
        let entry = engine.historyEntries.first { $0.sourceTimerID == done.id }
        XCTAssertEqual(entry?.outcome, .completed)
        XCTAssertEqual(entry?.resolution, .markDone)
        XCTAssertEqual(entry?.plannedDuration, 25 * 60)
        XCTAssertEqual(entry.map { $0.endedAt.timeIntervalSince($0.startedAt) }, 10 * 60)
        XCTAssertEqual(TimerHistoryInsights.calculate(entries: engine.historyEntries).completedCount, 1)

        // The finished timer must not fire at its original deadline.
        clock.date.addTimeInterval(20 * 60)
        engine.processExpiries()

        XCTAssertEqual(engine.pendingExpiries.map(\.timer.id), [other.id])
        XCTAssertEqual(audio.playedLabels, ["Tea"])
        XCTAssertEqual(engine.historyEntries.filter { $0.sourceTimerID == done.id }.count, 1)
    }

    @MainActor
    func testMarkDoneCompletesPausedTimerAndSurvivesRelaunch() {
        let directory = temporaryDirectory()
        let clock = TestClock(Date(timeIntervalSinceReferenceDate: 12_000))
        var engine: TimerEngine? = makeEngine(directory: directory, clock: clock)
        defer { try? FileManager.default.removeItem(at: directory) }
        let timer = engine!.createTimer(duration: 300, options: TimerOptions(label: "Paused"))
        engine!.pause(id: timer.id)

        engine!.markDone(id: timer.id)
        engine!.markDone(id: timer.id)
        engine = nil
        clock.date.addTimeInterval(301)

        let restored = makeEngine(directory: directory, clock: clock)

        XCTAssertTrue(restored.timers.isEmpty)
        XCTAssertTrue(restored.pendingExpiries.isEmpty)
        XCTAssertEqual(restored.historyEntries.map(\.outcome), [.completed])
        XCTAssertEqual(restored.historyEntries.map(\.resolution), [.markDone])
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
    func testATimerThatFinishesDuringAnotherAlertIsHeardWhenThatAlertEnds() {
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
        engine.createTimer(duration: 60, options: TimerOptions(label: "Tea", speaksName: true))
        engine.createTimer(duration: 62, options: TimerOptions(label: "Eggs"))

        clock.date.addTimeInterval(60)
        engine.processExpiries()
        // Tea's sound and its name take a few seconds; Eggs ends meanwhile.
        clock.date.addTimeInterval(2)
        engine.processExpiries()
        XCTAssertEqual(audio.playedLabels, ["Tea"])

        audio.finish()
        XCTAssertEqual(audio.playedLabels, ["Tea", "Eggs"])
        XCTAssertEqual(engine.activeAlert?.label, "Eggs")

        audio.finish()
        XCTAssertEqual(audio.playedLabels, ["Tea", "Eggs"])
        XCTAssertNil(engine.activeAlert)
    }

    @MainActor
    func testEveryTimerThatFinishesDuringAnAlertIsHeardInTheOrderItArrived() {
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
        engine.createTimer(duration: 60, options: TimerOptions(label: "Tea", speaksName: true))
        engine.createTimer(duration: 61, options: TimerOptions(label: "Eggs"))
        engine.createTimer(duration: 62, options: TimerOptions(label: "Toast"))
        let answered = engine.createTimer(duration: 63, options: TimerOptions(label: "Answered"))

        clock.date.addTimeInterval(60)
        engine.processExpiries()
        for _ in 0..<3 {
            clock.date.addTimeInterval(1)
            engine.processExpiries()
        }
        XCTAssertEqual(audio.playedLabels, ["Tea"])
        // Answered before its turn: it has nothing left to say.
        engine.markExpiryDone(id: engine.pendingExpiries.first { $0.timer.id == answered.id }!.id)

        audio.finish()
        XCTAssertEqual(audio.playedLabels, ["Tea", "Eggs"])
        audio.finish()
        XCTAssertEqual(audio.playedLabels, ["Tea", "Eggs", "Toast"])
        audio.finish()
        XCTAssertEqual(audio.playedLabels, ["Tea", "Eggs", "Toast"])
        XCTAssertNil(engine.activeAlert)
    }

    @MainActor
    func testAnsweringTheTimerThatIsSoundingGivesTheNextOneItsTurn() {
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
        let tea = engine.createTimer(duration: 60, options: TimerOptions(label: "Tea"))
        engine.createTimer(duration: 61, options: TimerOptions(label: "Eggs"))
        engine.createTimer(duration: 62, options: TimerOptions(label: "Toast"))
        clock.date.addTimeInterval(60)
        engine.processExpiries()
        for _ in 0..<2 {
            clock.date.addTimeInterval(1)
            engine.processExpiries()
        }

        // Tea is still sounding when it is answered.
        engine.markExpiryDone(id: engine.pendingExpiries.first { $0.timer.id == tea.id }!.id)
        XCTAssertEqual(audio.playedLabels, ["Tea", "Eggs"])
        XCTAssertEqual(engine.activeAlert?.label, "Eggs")

        audio.finish()
        XCTAssertEqual(audio.playedLabels, ["Tea", "Eggs", "Toast"])
        audio.finish()
        XCTAssertEqual(audio.playedLabels, ["Tea", "Eggs", "Toast"])
    }

    @MainActor
    func testTimersThatFinishTogetherEachSayTheNameTheyWereAskedToSay() {
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
            TimerTemplate(duration: 60, options: TimerOptions(label: "Plain"), origin: .routine),
            TimerTemplate(duration: 60, options: TimerOptions(label: "Tea", speaksName: true), origin: .routine),
            TimerTemplate(duration: 60, options: TimerOptions(label: "Eggs", speaksName: true), origin: .routine)
        ])
        engine.createTimer(duration: 61, options: TimerOptions(label: "Later"))

        clock.date.addTimeInterval(60)
        engine.processExpiries()
        clock.date.addTimeInterval(1)
        engine.processExpiries()
        XCTAssertEqual(audio.playedLabels.count, 1)
        for _ in 0..<5 { audio.finish() }

        // One alert stands for the three, and whichever of them it was, the
        // two names are both said before the timer that came later rings.
        let together = audio.playedLabels.dropLast()
        XCTAssertEqual(audio.playedLabels.last, "Later")
        XCTAssertTrue(Set(together).isSuperset(of: ["Tea", "Eggs"]), "\(audio.playedLabels)")
        XCTAssertEqual(together.count, together.first == "Plain" ? 3 : 2, "\(audio.playedLabels)")
        XCTAssertFalse(together.dropFirst().contains("Plain"))
        XCTAssertNil(engine.activeAlert)
    }

    @MainActor
    func testATimerProcessedLateKeepsTheTimeItWasDue() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let timer = fixture.engine.createTimer(duration: 60, options: TimerOptions(label: "Slept through"))

        // The Mac woke half an hour after the timer was due.
        fixture.clock.date.addTimeInterval(60 + 30 * 60)
        fixture.engine.processExpiries()

        let expiry = fixture.engine.pendingExpiries.first
        XCTAssertEqual(expiry?.expiredAt, fixture.clock.date)
        XCTAssertEqual(expiry?.dueAt, timer.fireDate)
    }

    @MainActor
    func testTimersThatFinishTogetherStillRingOnceAndSilencingDropsWaitingAlerts() {
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
        engine.createTimer(duration: 60, options: TimerOptions(label: "One"))
        engine.createTimer(duration: 60, options: TimerOptions(label: "Two"))
        engine.createTimer(duration: 62, options: TimerOptions(label: "Later"))

        clock.date.addTimeInterval(60)
        engine.processExpiries()
        XCTAssertEqual(audio.playedLabels.count, 1)
        audio.finish()
        XCTAssertEqual(audio.playedLabels.count, 1, "One alert speaks for timers that finish in the same instant")

        clock.date.addTimeInterval(2)
        engine.processExpiries()
        XCTAssertEqual(audio.playedLabels.last, "Later")
        engine.createTimer(duration: 1, options: TimerOptions(label: "Waiting"))
        clock.date.addTimeInterval(1)
        engine.processExpiries()
        engine.silenceExpiryAudio()
        audio.finish()
        XCTAssertEqual(audio.playedLabels.last, "Later", "Stop sound must stay silent")
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
