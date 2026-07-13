import AppKit
import Combine
import Foundation

final class TimerEngine: ObservableObject {
    @Published private(set) var timers: [TimerRecord] = []
    @Published private(set) var pendingExpiries: [PendingExpiry] = []
    @Published private(set) var historyEntries: [TimerHistoryEntry] = []
    @Published private(set) var activeAlert: TimerRecord?

    private var heap = DeadlineHeap()
    private let persistence: TimerPersistence
    private let historyStore: TimerHistoryStore
    private let pendingExpiryStore: PendingExpiryStore
    private let notificationService: NotificationService
    private let audioPlayer: AudioAlertPlaying
    private let shouldFirePastDueOnWake: () -> Bool
    private let now: () -> Date
    private let scheduler: DispatchSourceTimer
    private var wakeObserver: NSObjectProtocol?
    private var activeAudioExpiryID: UUID?

    init(
        persistence: TimerPersistence,
        historyStore: TimerHistoryStore? = nil,
        pendingExpiryStore: PendingExpiryStore? = nil,
        notificationService: NotificationService,
        audioPlayer: AudioAlertPlaying,
        shouldFirePastDueOnWake: @escaping () -> Bool = { true },
        now: @escaping () -> Date = Date.init
    ) {
        self.persistence = persistence
        let directory = persistence.fileURL.deletingLastPathComponent()
        self.historyStore = historyStore
            ?? TimerHistoryStore(fileURL: directory.appendingPathComponent("history.json"))
        self.pendingExpiryStore = pendingExpiryStore
            ?? PendingExpiryStore(fileURL: directory.appendingPathComponent("pending-expiries.json"))
        self.notificationService = notificationService
        self.audioPlayer = audioPlayer
        self.shouldFirePastDueOnWake = shouldFirePastDueOnWake
        self.now = now
        scheduler = DispatchSource.makeTimerSource(queue: .main)

        scheduler.setEventHandler { [weak self] in
            self?.processExpiries()
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

        loadPersistedState()
        audioPlayer.setPlaybackFinishedHandler { [weak self] in
            self?.audioPlaybackDidFinish()
        }
        notificationService.setActionHandler { [weak self] timerID, action in
            self?.handleNotificationAction(timerID: timerID, action: action)
        }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        scheduler.setEventHandler {}
        scheduler.cancel()
    }

    var currentExpiry: PendingExpiry? { pendingExpiries.first }

    func requestNotificationAuthorization() {
        notificationService.requestAuthorization()
    }

    @discardableResult
    func createTimer(template: TimerTemplate) -> TimerRecord {
        createTimer(
            duration: template.duration,
            options: template.options,
            origin: template.origin,
            parentEventID: template.parentEventID
        )
    }

    @discardableResult
    func createTimer(
        duration: TimeInterval,
        options: TimerOptions,
        origin: TimerOrigin = .drag,
        parentEventID: UUID? = nil
    ) -> TimerRecord {
        let createdAt = now()
        let normalizedDuration = min(max(1, duration.rounded()), 24 * 60 * 60)
        let record = TimerRecord(
            createdAt: createdAt,
            fireDate: createdAt.addingTimeInterval(normalizedDuration),
            options: options,
            origin: origin,
            parentEventID: parentEventID
        )
        insert(record, scheduleNotification: true)
        return record
    }

    @discardableResult
    func createTimer(
        fireDate: Date,
        options: TimerOptions,
        origin: TimerOrigin = .drag
    ) -> TimerRecord {
        let createdAt = now()
        let record = TimerRecord(
            createdAt: createdAt,
            fireDate: fireDate,
            options: options,
            origin: origin
        )
        let isPastDue = fireDate <= createdAt
        insert(record, scheduleNotification: !isPastDue)
        if isPastDue {
            notificationService.deliverImmediately(record)
            processExpiries(at: createdAt)
        }
        return record
    }

    func update(_ timer: TimerRecord) {
        guard let index = timers.firstIndex(where: { $0.id == timer.id }) else { return }
        if timer.isPaused {
            heap.remove(id: timer.id)
        } else if !heap.replace(timer) {
            heap.insert(timer)
        }
        timers[index] = timer
        sortTimers()
        notificationService.remove(timerID: timer.id)
        if !timer.isPaused {
            notificationService.schedule(timer)
        }
        persistActiveTimers()
        rearmScheduler()
    }

    func cancel(id: UUID) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }
        appendHistory(TimerHistoryEntry(timer: timer, endedAt: now(), outcome: .cancelled))
        heap.remove(id: id)
        timers.removeAll { $0.id == id }
        notificationService.remove(timerID: id)
        persistHistory()
        persistActiveTimers()
        rearmScheduler()
    }

    /// Moves an active timer to its snooze duration without ending its current
    /// lifecycle. Expiry-card snooze uses `snoozeExpiry(id:)` instead.
    func snooze(id: UUID) {
        guard var timer = timers.first(where: { $0.id == id }) else { return }
        let duration = TimeInterval(timer.snoozeMinutes * 60)
        timer.originalDuration = duration
        timer.pausedRemaining = nil
        timer.fireDate = now().addingTimeInterval(duration)
        update(timer)
    }

    func pause(id: UUID) {
        guard var timer = timers.first(where: { $0.id == id }), !timer.isPaused else { return }
        timer.pausedRemaining = max(1, timer.remaining(at: now()).rounded(.up))
        update(timer)
    }

    func resume(id: UUID) {
        guard var timer = timers.first(where: { $0.id == id }),
              let remaining = timer.pausedRemaining else { return }
        timer.pausedRemaining = nil
        timer.fireDate = now().addingTimeInterval(max(1, remaining))
        update(timer)
    }

    func reset(id: UUID) {
        guard var timer = timers.first(where: { $0.id == id }) else { return }
        let duration = timer.resetDuration
        if timer.isPaused {
            timer.pausedRemaining = duration
        } else {
            timer.fireDate = now().addingTimeInterval(duration)
        }
        update(timer)
    }

    func cancelAll() {
        let endedAt = now()
        for timer in timers {
            appendHistory(TimerHistoryEntry(timer: timer, endedAt: endedAt, outcome: .cancelled))
            notificationService.remove(timerID: timer.id)
        }
        heap = DeadlineHeap()
        timers.removeAll()
        silenceExpiryAudio()
        persistHistory()
        persistActiveTimers()
        rearmScheduler()
    }

    func silenceExpiryAudio() {
        audioPlayer.stop()
        activeAlert = nil
        activeAudioExpiryID = nil
    }

    func stopActiveAlert() {
        silenceExpiryAudio()
    }

    @discardableResult
    func snoozeExpiry(id: UUID) -> TimerRecord? {
        resolveExpiry(id: id, as: .snoozed)
    }

    @discardableResult
    func restartExpiry(id: UUID) -> TimerRecord? {
        resolveExpiry(id: id, as: .restarted)
    }

    func markExpiryDone(id: UUID) {
        _ = resolveExpiry(id: id, as: .markDone)
    }

    @discardableResult
    func restartHistoryEntry(id: UUID) -> TimerRecord? {
        guard let entry = historyEntries.first(where: { $0.id == id }) else { return nil }
        return createTimer(
            duration: entry.plannedDuration,
            options: entry.optionsSnapshot,
            origin: .history,
            parentEventID: entry.id
        )
    }

    func clearHistory() {
        historyEntries.removeAll()
        persistHistory()
    }

    func flushPersistence() {
        persistPendingExpiries()
        persistHistory()
        persistActiveTimers()
    }

    /// Internal for deterministic lifecycle tests.
    func processExpiries(at date: Date? = nil) {
        let currentDate = date ?? now()
        var expiredTimers: [TimerRecord] = []
        while let next = heap.peek, next.fireDate <= currentDate, let expired = heap.pop() {
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
            let expiry = PendingExpiry(timer: timer, expiredAt: currentDate)
            pendingExpiries.append(expiry)
            appendHistory(TimerHistoryEntry(
                id: expiry.id,
                timer: timer,
                endedAt: currentDate,
                outcome: .completed
            ))
        }
        sortPendingExpiries()

        // Persist pending first. If the app exits before history or timers are
        // saved, launch reconciliation can finish the transition without a
        // duplicate terminal event.
        persistPendingExpiries()
        persistHistory()
        persistActiveTimers()
        chooseAudioExpiry(from: pendingExpiries.filter { expiredIDs.contains($0.timer.id) })
        rearmScheduler()
    }

    private func loadPersistedState() {
        let currentDate = now()
        historyEntries = historyStore.load(now: currentDate)
        pendingExpiries = pendingExpiryStore.load()
        let restoredTimers = (try? persistence.load()) ?? []

        // A crash can leave a terminal timer in timers.json after its pending
        // event was safely persisted. Terminal source IDs must never re-enter
        // the active heap.
        let terminalTimerIDs = Set(historyEntries.map(\.sourceTimerID))
            .union(pendingExpiries.map { $0.timer.id })
        timers = restoredTimers.filter { !terminalTimerIDs.contains($0.id) }

        // Repair a crash between pending-expiry and history writes.
        for expiry in pendingExpiries where !historyEntries.contains(where: { $0.id == expiry.id }) {
            appendHistory(TimerHistoryEntry(
                id: expiry.id,
                timer: expiry.timer,
                endedAt: expiry.expiredAt,
                outcome: .completed
            ))
        }
        // Resolution persistence writes a child timer (if any), then history,
        // then removes the pending event. Reconcile either committed marker so
        // a crash cannot create a second snooze/restart child.
        var resolvedPendingIDs = Set<UUID>()
        for expiry in pendingExpiries {
            if let historyIndex = historyEntries.firstIndex(where: { $0.id == expiry.id }),
               historyEntries[historyIndex].resolution != nil {
                resolvedPendingIDs.insert(expiry.id)
                continue
            }
            guard let child = timers.first(where: { $0.parentEventID == expiry.id }) else { continue }
            let inferredResolution: ExpiryResolution?
            switch child.resolvedOrigin {
            case .snooze: inferredResolution = .snoozed
            case .restart: inferredResolution = .restarted
            case .drag, .preset, .history: inferredResolution = nil
            }
            guard let inferredResolution,
                  let historyIndex = historyEntries.firstIndex(where: { $0.id == expiry.id }) else { continue }
            historyEntries[historyIndex].outcome = .completed
            historyEntries[historyIndex].resolution = inferredResolution
            historyEntries[historyIndex].linkedTimerID = child.id
            resolvedPendingIDs.insert(expiry.id)
        }
        pendingExpiries.removeAll { resolvedPendingIDs.contains($0.id) }
        sortPendingExpiries()

        for timer in timers where !timer.isPaused {
            heap.insert(timer)
            if timer.fireDate > currentDate {
                notificationService.schedule(timer)
            }
        }
        sortTimers()
        persistPendingExpiries()
        persistHistory()
        persistActiveTimers()

        if shouldFirePastDueOnWake() {
            processExpiries(at: currentDate)
        } else {
            discardPastDueTimers(at: currentDate)
        }
        rearmScheduler()
    }

    private func insert(_ timer: TimerRecord, scheduleNotification: Bool) {
        heap.insert(timer)
        timers.append(timer)
        sortTimers()
        if scheduleNotification {
            notificationService.schedule(timer)
        }
        persistActiveTimers()
        rearmScheduler()
    }

    private func resolveExpiry(id: UUID, as resolution: ExpiryResolution) -> TimerRecord? {
        guard let expiryIndex = pendingExpiries.firstIndex(where: { $0.id == id }) else { return nil }
        let expiry = pendingExpiries[expiryIndex]
        var child: TimerRecord?
        let childDuration: TimeInterval?
        let childOrigin: TimerOrigin?
        switch resolution {
        case .markDone:
            childDuration = nil
            childOrigin = nil
        case .snoozed:
            childDuration = TimeInterval(expiry.timer.snoozeMinutes * 60)
            childOrigin = .snooze
        case .restarted:
            childDuration = expiry.timer.resetDuration
            childOrigin = .restart
        }

        if let childDuration, let childOrigin {
            let createdAt = now()
            let record = TimerRecord(
                createdAt: createdAt,
                fireDate: createdAt.addingTimeInterval(childDuration),
                options: expiry.timer.options,
                origin: childOrigin,
                parentEventID: expiry.id
            )
            heap.insert(record)
            timers.append(record)
            sortTimers()
            notificationService.schedule(record)
            child = record
        }

        if let historyIndex = historyEntries.firstIndex(where: { $0.id == expiry.id }) {
            historyEntries[historyIndex].outcome = .completed
            historyEntries[historyIndex].resolution = resolution
            historyEntries[historyIndex].linkedTimerID = child?.id
        } else {
            appendHistory(TimerHistoryEntry(
                id: expiry.id,
                timer: expiry.timer,
                endedAt: expiry.expiredAt,
                outcome: .completed,
                resolution: resolution,
                linkedTimerID: child?.id
            ))
        }
        pendingExpiries.remove(at: expiryIndex)

        if activeAudioExpiryID == expiry.id {
            silenceExpiryAudio()
            chooseAudioExpiry(from: pendingExpiries)
        }
        // Commit any child first, then the idempotent history resolution, and
        // remove the pending event last. Launch reconciliation understands
        // both intermediate states.
        persistActiveTimers()
        persistHistory()
        persistPendingExpiries()
        rearmScheduler()
        return child
    }

    private func chooseAudioExpiry(from candidates: [PendingExpiry]) {
        guard activeAudioExpiryID == nil else { return }
        let candidate = candidates.last(where: { $0.timer.loop }) ?? candidates.last
        guard let candidate else { return }
        audioPlayer.play(timer: candidate.timer)
        activeAudioExpiryID = candidate.id
        activeAlert = candidate.timer
    }

    private func audioPlaybackDidFinish() {
        guard activeAlert?.loop != true else { return }
        activeAudioExpiryID = nil
        activeAlert = nil
    }

    /// Internal for deterministic notification-action lifecycle tests.
    func handleNotificationAction(timerID: UUID, action: NotificationTimerAction) {
        // If the app was launched by the action, state reconciliation has
        // already converted a past-due active timer into a pending expiry.
        let expiry: PendingExpiry
        if let pending = pendingExpiries.first(where: { $0.timer.id == timerID }) {
            expiry = pending
        } else {
            // When missed timers are configured not to fire, wake/launch keeps
            // only a discarded history snapshot. A notification may already
            // have been delivered by macOS, so restore actionable state only
            // after the user explicitly taps one of its actions.
            guard let entry = historyEntries.first(where: {
                $0.sourceTimerID == timerID && $0.outcome == .discarded && $0.resolution == nil
            }) else { return }
            let restoredTimer = TimerRecord(
                id: entry.sourceTimerID,
                createdAt: entry.startedAt,
                fireDate: entry.startedAt.addingTimeInterval(entry.plannedDuration),
                options: entry.optionsSnapshot,
                origin: entry.origin,
                parentEventID: entry.parentEventID
            )
            expiry = PendingExpiry(id: entry.id, timer: restoredTimer, expiredAt: entry.endedAt)
            pendingExpiries.append(expiry)
            sortPendingExpiries()
            persistPendingExpiries()
        }
        switch action {
        case .snooze: _ = snoozeExpiry(id: expiry.id)
        case .markDone: markExpiryDone(id: expiry.id)
        case .restart: _ = restartExpiry(id: expiry.id)
        }
    }

    private func handleWake() {
        if shouldFirePastDueOnWake() {
            processExpiries()
        } else {
            discardPastDueTimers(at: now())
        }
        rearmScheduler()
    }

    private func discardPastDueTimers(at date: Date) {
        var discarded: [TimerRecord] = []
        while let next = heap.peek, next.fireDate <= date, let expired = heap.pop() {
            discarded.append(expired)
        }
        guard !discarded.isEmpty else { return }
        let discardedIDs = Set(discarded.map(\.id))
        timers.removeAll { discardedIDs.contains($0.id) }
        for timer in discarded {
            notificationService.remove(timerID: timer.id)
            appendHistory(TimerHistoryEntry(timer: timer, endedAt: date, outcome: .discarded))
        }
        persistHistory()
        persistActiveTimers()
    }

    private func appendHistory(_ entry: TimerHistoryEntry) {
        if let index = historyEntries.firstIndex(where: { $0.id == entry.id }) {
            historyEntries[index] = entry
        } else {
            historyEntries.append(entry)
        }
        historyEntries = historyStore.retained(historyEntries, now: now())
    }

    private func rearmScheduler() {
        guard let next = heap.peek else {
            scheduler.schedule(deadline: .distantFuture)
            return
        }
        let interval = max(0, next.fireDate.timeIntervalSince(now()))
        scheduler.schedule(deadline: .now() + interval, repeating: .never, leeway: .milliseconds(25))
    }

    private func persistActiveTimers() { try? persistence.save(timers) }
    private func persistHistory() { try? historyStore.save(historyEntries, now: now()) }
    private func persistPendingExpiries() { try? pendingExpiryStore.save(pendingExpiries) }

    private func sortTimers() {
        timers.sort { lhs, rhs in
            if lhs.isPaused != rhs.isPaused { return !lhs.isPaused }
            if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func sortPendingExpiries() {
        pendingExpiries.sort { lhs, rhs in
            if lhs.expiredAt != rhs.expiredAt { return lhs.expiredAt < rhs.expiredAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
