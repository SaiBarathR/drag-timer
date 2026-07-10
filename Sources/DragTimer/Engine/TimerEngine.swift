import AppKit
import Combine
import Foundation

final class TimerEngine: ObservableObject {
    @Published private(set) var timers: [TimerRecord] = []
    @Published private(set) var activeAlert: TimerRecord?

    private var heap = DeadlineHeap()
    private let persistence: TimerPersistence
    private let notificationService: NotificationService
    private let audioPlayer: AudioAlertPlaying
    private let shouldFirePastDueOnWake: () -> Bool
    private let scheduler: DispatchSourceTimer
    private var wakeObserver: NSObjectProtocol?

    init(
        persistence: TimerPersistence,
        notificationService: NotificationService,
        audioPlayer: AudioAlertPlaying,
        shouldFirePastDueOnWake: @escaping () -> Bool = { true }
    ) {
        self.persistence = persistence
        self.notificationService = notificationService
        self.audioPlayer = audioPlayer
        self.shouldFirePastDueOnWake = shouldFirePastDueOnWake
        self.scheduler = DispatchSource.makeTimerSource(queue: .main)

        scheduler.setEventHandler { [weak self] in
            self?.handleSchedulerFire()
        }
        scheduler.schedule(deadline: .distantFuture)
        scheduler.resume()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }

        loadPersistedTimers()
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        scheduler.setEventHandler {}
        scheduler.cancel()
    }

    func requestNotificationAuthorization() {
        notificationService.requestAuthorization()
    }

    @discardableResult
    func createTimer(duration: TimeInterval, options: TimerOptions) -> TimerRecord {
        let record = TimerRecord(
            fireDate: Date().addingTimeInterval(max(1, duration.rounded())),
            options: options
        )
        insert(record, scheduleNotification: true)
        return record
    }

    func update(_ timer: TimerRecord) {
        guard heap.replace(timer), let index = timers.firstIndex(where: { $0.id == timer.id }) else { return }
        timers[index] = timer
        timers.sort { $0.fireDate < $1.fireDate }
        notificationService.remove(timerID: timer.id)
        notificationService.schedule(timer)
        persist()
        rearmScheduler()
    }

    func cancel(id: UUID) {
        guard heap.remove(id: id) != nil else { return }
        timers.removeAll { $0.id == id }
        notificationService.remove(timerID: id)
        persist()
        rearmScheduler()
    }

    func snooze(id: UUID) {
        guard var timer = timers.first(where: { $0.id == id }) else { return }
        timer.fireDate = Date().addingTimeInterval(TimeInterval(timer.snoozeMinutes * 60))
        update(timer)
    }

    func stopActiveAlert() {
        audioPlayer.stop()
        activeAlert = nil
    }

    func flushPersistence() {
        persist()
    }

    private func loadPersistedTimers() {
        guard let restoredTimers = try? persistence.load() else {
            rearmScheduler()
            return
        }

        for timer in restoredTimers {
            heap.insert(timer)
            timers.append(timer)
            notificationService.schedule(timer)
        }
        timers.sort { $0.fireDate < $1.fireDate }

        if shouldFirePastDueOnWake() {
            handleSchedulerFire()
        } else {
            discardPastDueTimers()
        }
        rearmScheduler()
    }

    private func insert(_ timer: TimerRecord, scheduleNotification: Bool) {
        heap.insert(timer)
        timers.append(timer)
        timers.sort { $0.fireDate < $1.fireDate }
        if scheduleNotification {
            notificationService.schedule(timer)
        }
        persist()
        rearmScheduler()
    }

    private func handleWake() {
        if shouldFirePastDueOnWake() {
            handleSchedulerFire()
        } else {
            discardPastDueTimers()
        }
        rearmScheduler()
    }

    private func handleSchedulerFire() {
        let now = Date()
        var expiredTimers: [TimerRecord] = []

        while let next = heap.peek, next.fireDate <= now, let expired = heap.pop() {
            expiredTimers.append(expired)
        }

        guard !expiredTimers.isEmpty else {
            rearmScheduler()
            return
        }

        let expiredIDs = Set(expiredTimers.map(\.id))
        timers.removeAll { expiredIDs.contains($0.id) }

        for timer in expiredTimers {
            notificationService.remove(timerID: timer.id)
        }

        // Multiple timers can expire in the same scheduler tick. Playing each
        // one in turn used to stop a looping alert when any later timer was
        // non-looping. Pick one audible alert, always preferring the looping
        // one, so it stays active until the user stops it.
        let loopingAlert = expiredTimers.last(where: \.loop)
        if let audibleAlert = loopingAlert ?? expiredTimers.last {
            audioPlayer.play(timer: audibleAlert)
        }
        activeAlert = loopingAlert

        persist()
        rearmScheduler()
    }

    private func discardPastDueTimers() {
        let now = Date()
        var discarded: [TimerRecord] = []

        while let next = heap.peek, next.fireDate <= now, let expired = heap.pop() {
            discarded.append(expired)
        }

        guard !discarded.isEmpty else { return }
        let discardedIDs = Set(discarded.map(\.id))
        timers.removeAll { discardedIDs.contains($0.id) }
        for timer in discarded {
            notificationService.remove(timerID: timer.id)
        }
        persist()
    }

    private func rearmScheduler() {
        guard let next = heap.peek else {
            scheduler.schedule(deadline: .distantFuture)
            return
        }

        let interval = max(0, next.fireDate.timeIntervalSinceNow)
        scheduler.schedule(
            deadline: .now() + interval,
            repeating: .never,
            leeway: .milliseconds(25)
        )
    }

    private func persist() {
        try? persistence.save(timers)
    }
}
