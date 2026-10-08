import AppKit
import Combine
import Foundation
import os

/// Timers that Cancel, Mark done or Stop all has just taken off the list,
/// kept for a few seconds so that one click can put them back.
struct TimerRemoval: Equatable, Identifiable {
    enum Kind: Equatable {
        case cancelled
        case markedDone
        case stoppedAll
    }

    let id = UUID()
    var kind: Kind
    var timers: [TimerRecord]
    var historyEntryIDs: [UUID]
    var removedAt: Date

    var summary: String {
        let name = timers.first?.label ?? "timer"
        switch kind {
        case .cancelled: return "Cancelled \(name)"
        case .markedDone: return "Marked \(name) done"
        case .stoppedAll: return "Stopped \(timers.count) \(timers.count == 1 ? "timer" : "timers")"
        }
    }
}

final class TimerEngine: ObservableObject {
    /// How long a removal can be undone.
    static let undoWindow: TimeInterval = 10

    @Published private(set) var timers: [TimerRecord] = []
    @Published private(set) var pendingExpiries: [PendingExpiry] = []
    @Published private(set) var historyEntries: [TimerHistoryEntry] = []
    @Published private(set) var activeAlert: TimerRecord?
    @Published private(set) var undoableRemoval: TimerRemoval?

    private static let logger = Logger(subsystem: "com.dragtimer.app", category: "persistence")

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
    /// Expiries that arrived while another alert was sounding, oldest first.
    /// Those that arrived together are one entry, as they would have shared
    /// one alert had nothing been sounding.
    private var waitingAudioExpiryIDs: [[UUID]] = []
    private var didRequestNotificationAuthorization = false
    private var permissionObservation: AnyCancellable?
    private var undoExpiry: DispatchWorkItem?

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
        permissionObservation = notificationService.$permissionState
            .scan((NotificationPermissionState.checking, NotificationPermissionState.checking)) { ($0.1, $1) }
            .sink { [weak self] previous, current in
                guard TimerEngine.permissionWasGranted(from: previous, to: current) else { return }
                self?.rescheduleNotifications()
            }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        scheduler.setEventHandler {}
        scheduler.cancel()
        undoExpiry?.cancel()
    }

    var currentExpiry: PendingExpiry? { pendingExpiries.first }

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
    func createTimers(templates: [TimerTemplate]) -> [TimerRecord] {
        guard !templates.isEmpty else { return [] }
        let createdAt = now()
        let records = templates.map { template in
            TimerRecord(
                createdAt: createdAt,
                fireDate: createdAt.addingTimeInterval(Self.clamped(template.duration)),
                options: template.options,
                origin: template.origin,
                parentEventID: template.parentEventID
            )
        }
        insert(records)
        return records
    }

    @discardableResult
    func createTimer(
        duration: TimeInterval,
        options: TimerOptions,
        origin: TimerOrigin = .drag,
        parentEventID: UUID? = nil
    ) -> TimerRecord {
        let createdAt = now()
        let record = TimerRecord(
            createdAt: createdAt,
            fireDate: createdAt.addingTimeInterval(Self.clamped(duration)),
            options: options,
            origin: origin,
            parentEventID: parentEventID
        )
        insert([record])
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
        endActiveTimer(id: id, outcome: .cancelled)
    }

    /// Completes an active timer before it fires: no alert, no expiry card.
    /// Expiry-card completion uses `markExpiryDone(id:)` instead.
    func markDone(id: UUID) {
        endActiveTimer(id: id, outcome: .completed, resolution: .markDone)
    }

    /// Removes an active timer as if it had never been created: no history
    /// entry. Used when a just-dragged timer is discarded from its name prompt.
    /// A timer that already rang while the prompt was open is dismissed like
    /// Mark done instead, so its card and sound do not outlive the discard.
    func discard(id: UUID) {
        let current = lineage(of: id).last ?? id
        if let expiry = pendingExpiries.first(where: { $0.timer.id == current }) {
            markExpiryDone(id: expiry.id)
        } else {
            endActiveTimer(id: current, outcome: nil)
        }
    }

    /// What a just-dragged timer is doing now. Its name prompt stays open
    /// over a timer that is already running, and that timer can ring, or be
    /// stopped or answered some other way, before it has been named.
    func nameableState(of id: UUID) -> NameableTimerState {
        let ids = lineage(of: id)
        if let timer = timers.last(where: { ids.contains($0.id) }) {
            return timer.pausedRemaining.map { .paused(remaining: $0) } ?? .running(fireDate: timer.fireDate)
        }
        if let expiry = pendingExpiries.last(where: { ids.contains($0.timer.id) }) {
            return .finished(dueAt: expiry.dueAt)
        }
        return .gone
    }

    /// The ids one dragged timer has gone by: its own, then the timer made by
    /// each snooze or restart of its expiry. The name prompt can still be
    /// open when that happens, and it only knows the first id.
    private func lineage(of id: UUID) -> [UUID] {
        var ids = [id]
        while ids.count < 32,
              let child = historyEntries.first(where: { $0.sourceTimerID == ids[ids.count - 1] })?.linkedTimerID,
              !ids.contains(child) {
            ids.append(child)
        }
        return ids
    }

    private func endActiveTimer(
        id: UUID,
        outcome: TimerHistoryOutcome?,
        resolution: ExpiryResolution? = nil
    ) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }
        let endedAt = now()
        let entry = outcome.map {
            TimerHistoryEntry(timer: timer, endedAt: endedAt, outcome: $0, resolution: resolution)
        }
        if let entry {
            appendHistory(entry)
            // Offered before the timer leaves the list, so that an observer
            // of both never finds it in neither. A discard has no entry and
            // is not offered back: it was asked for by name, from the prompt
            // that had only just created the timer.
            offerUndo(TimerRemoval(
                kind: entry.outcome == .cancelled ? .cancelled : .markedDone,
                timers: [timer],
                historyEntryIDs: [entry.id],
                removedAt: endedAt
            ))
        }
        heap.remove(id: id)
        timers.removeAll { $0.id == id }
        notificationService.remove(timerID: id)
        persistHistory()
        persistActiveTimers()
        rearmScheduler()
    }

    /// Puts back what the last Cancel, Mark done or Stop all removed, with
    /// the end times the timers had, and takes their entries out of history.
    /// A timer whose end has passed in the meantime rings at once.
    func undoLastRemoval() {
        guard let removal = undoableRemoval else { return }
        guard now().timeIntervalSince(removal.removedAt) <= Self.undoWindow else {
            // The offer outlived its window, as it can across a sleep.
            dismissUndo()
            return
        }
        let entryIDs = Set(removal.historyEntryIDs)
        historyEntries.removeAll { entryIDs.contains($0.id) }
        requestNotificationAuthorizationOnce()
        for timer in removal.timers where !timers.contains(where: { $0.id == timer.id }) {
            timers.append(timer)
            guard !timer.isPaused else { continue }
            heap.insert(timer)
            // One that is already due rings in the app at once; a banner
            // scheduled now would arrive after it.
            if timer.fireDate > now() {
                notificationService.schedule(timer)
            }
        }
        sortTimers()
        // Withdrawn only once the timers are back, for the same observer.
        dismissUndo()
        // Timers first. Launch treats a timer that also has a history entry
        // as ended, so a crash between the two writes leaves the removal
        // standing instead of losing the timer from both files.
        persistActiveTimers()
        persistHistory()
        rearmScheduler()
    }

    func dismissUndo() {
        undoExpiry?.cancel()
        undoExpiry = nil
        undoableRemoval = nil
    }

    private func offerUndo(_ removal: TimerRemoval) {
        undoExpiry?.cancel()
        undoableRemoval = removal
        let expiry = DispatchWorkItem { [weak self] in
            guard let self, self.undoableRemoval?.id == removal.id else { return }
            self.undoableRemoval = nil
        }
        undoExpiry = expiry
        // The wall clock, like `removedAt`, so the offer does not outlive
        // its window by however long the Mac was asleep.
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + Self.undoWindow, execute: expiry)
    }

    /// Pushes an active timer back by its snooze length. The planned duration
    /// is untouched, so Reset still returns to what was originally set, and a
    /// paused timer stays paused. Expiry-card snooze uses `snoozeExpiry(id:)`.
    func addTime(id: UUID) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }
        adjustTime(id: id, by: TimeInterval(timer.snoozeMinutes * 60))
    }

    /// Moves an active timer's end later or earlier. Like `addTime(id:)` it
    /// leaves the planned duration and a pause alone. A change that would
    /// leave less than a second to run is ignored; ending a timer early is
    /// what Mark done and Cancel are for.
    func adjustTime(id: UUID, by change: TimeInterval) {
        guard var timer = timers.first(where: { $0.id == id }),
              timer.remaining(at: now()) + change >= 1 else { return }
        if let remaining = timer.pausedRemaining {
            timer.pausedRemaining = remaining + change
        } else {
            timer.fireDate = timer.fireDate.addingTimeInterval(change)
        }
        update(timer)
    }

    /// Starts an active timer's countdown again at a new length. That length
    /// becomes its planned duration, so Reset, the progress ring and history
    /// all follow it. A paused timer stays paused.
    func setRemaining(id: UUID, to duration: TimeInterval) {
        guard var timer = timers.first(where: { $0.id == id }) else { return }
        let duration = Self.clamped(duration)
        timer.originalDuration = duration
        if timer.isPaused {
            timer.pausedRemaining = duration
        } else {
            timer.fireDate = now().addingTimeInterval(duration)
        }
        update(timer)
    }

    /// Also reaches a timer that expired meanwhile, and one that was snoozed
    /// or restarted from that expiry, so the expiry card, the history entries
    /// and the running successor all carry the new name.
    func rename(id: UUID, to label: String) {
        let ids = lineage(of: id)
        let expiryIndices = pendingExpiries.indices.filter { ids.contains(pendingExpiries[$0].timer.id) }
        let historyIndices = historyEntries.indices.filter { ids.contains(historyEntries[$0].sourceTimerID) }
        for index in expiryIndices {
            pendingExpiries[index].timer.label = label
        }
        for index in historyIndices {
            historyEntries[index].label = label
            historyEntries[index].optionsSnapshot.label = label
        }
        if !expiryIndices.isEmpty { persistPendingExpiries() }
        if !historyIndices.isEmpty { persistHistory() }
        if var timer = timers.first(where: { ids.contains($0.id) }) {
            timer.label = label
            update(timer)
        }
        // Stopped while its name was being typed, it comes back from Undo
        // under that name.
        if var removal = undoableRemoval {
            let removed = removal.timers.indices.filter { ids.contains(removal.timers[$0].id) }
            for index in removed {
                removal.timers[index].label = label
            }
            if !removed.isEmpty { undoableRemoval = removal }
        }
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
        let stopped = timers
        var entryIDs: [UUID] = []
        for timer in stopped {
            let entry = TimerHistoryEntry(timer: timer, endedAt: endedAt, outcome: .cancelled)
            appendHistory(entry)
            entryIDs.append(entry.id)
            notificationService.remove(timerID: timer.id)
        }
        if !stopped.isEmpty {
            offerUndo(TimerRemoval(
                kind: .stoppedAll,
                timers: stopped,
                historyEntryIDs: entryIDs,
                removedAt: endedAt
            ))
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
        waitingAudioExpiryIDs.removeAll()
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
        // Starting a just-removed timer again answers the offer for that
        // timer; otherwise Undo would bring back a second copy. The rest of
        // a Stop all stays on offer.
        if var removal = undoableRemoval, let index = removal.historyEntryIDs.firstIndex(of: id) {
            removal.historyEntryIDs.remove(at: index)
            removal.timers.removeAll { $0.id == entry.sourceTimerID }
            if removal.timers.isEmpty {
                dismissUndo()
            } else {
                undoableRemoval = removal
            }
        }
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
        // Published after the pending expiries: an observer of both lists
        // must never see a timer that has finished in neither of them.
        timers.removeAll { expiredIDs.contains($0.id) }

        // Persist pending first. If the app exits before history or timers are
        // saved, launch reconciliation can finish the transition without a
        // duplicate terminal event.
        persistPendingExpiries()
        persistHistory()
        persistActiveTimers()
        startAlert(for: pendingExpiries.filter { expiredIDs.contains($0.timer.id) })
        rearmScheduler()
    }

    private func loadPersistedState() {
        let currentDate = now()
        historyEntries = historyStore.load(now: currentDate)
        pendingExpiries = pendingExpiryStore.load()
        let restoredTimers = persistence.loadSalvagingReadableTimers()

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
            case .drag, .preset, .routine, .history: inferredResolution = nil
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

        if !timers.isEmpty {
            requestNotificationAuthorizationOnce()
        }
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

    private static func clamped(_ duration: TimeInterval) -> TimeInterval {
        min(max(1, duration.rounded()), 24 * 60 * 60)
    }

    private func insert(_ records: [TimerRecord]) {
        activate(records)
        persistActiveTimers()
        rearmScheduler()
    }

    /// Puts new timers into the heap, the sorted list and the notification
    /// schedule. Persisting is left to the caller, whose write order matters
    /// for crash recovery.
    private func activate(_ records: [TimerRecord]) {
        requestNotificationAuthorizationOnce()
        for record in records {
            heap.insert(record)
            timers.append(record)
            notificationService.schedule(record)
        }
        sortTimers()
    }

    /// Asked when a timer first becomes active (started, snoozed, restarted
    /// or restored at launch) rather than on every launch, so the system
    /// prompt arrives when its purpose is obvious. macOS only shows it while
    /// the permission is undetermined.
    private func requestNotificationAuthorizationOnce() {
        guard !didRequestNotificationAuthorization else { return }
        didRequestNotificationAuthorization = true
        notificationService.requestAuthorization()
    }

    /// macOS refuses notification requests made before permission exists, so
    /// timers started earlier need scheduling again when it is granted,
    /// whether from the system prompt or later in System Settings.
    static func permissionWasGranted(
        from previous: NotificationPermissionState,
        to current: NotificationPermissionState
    ) -> Bool {
        [.notDetermined, .denied].contains(previous) && [.authorized, .provisional].contains(current)
    }

    private func rescheduleNotifications() {
        for timer in timers where !timer.isPaused {
            notificationService.schedule(timer)
        }
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
            activate([record])
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
            // Answering the timer that is sounding ends its alert, not the
            // turn of those waiting behind it. Nothing that is not waiting
            // is started: a timer that has had its alert, or was silenced,
            // stays quiet.
            audioPlayer.stop()
            activeAlert = nil
            activeAudioExpiryID = nil
            soundNextWaitingAlert()
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

    /// Sounds the alert for expiries that arrived together, or queues it
    /// behind the one that is sounding now, so that a timer ending a second
    /// or two after another is not silent.
    private func startAlert(for arrived: [PendingExpiry]) {
        guard activeAudioExpiryID == nil else {
            waitingAudioExpiryIDs.append(arrived.map(\.id))
            return
        }
        chooseAudioExpiry(from: arrived)
        guard let sounding = activeAudioExpiryID else { return }
        // One alert speaks for timers that finish in the same instant, but
        // a name that was asked for is still said, and an alarm that loops
        // is still heard until it is stopped: those of the others go next,
        // ahead of anything that arrived later.
        let owed = arrived.filter { $0.id != sounding && ($0.timer.loop || $0.timer.speaksName == true) }
        waitingAudioExpiryIDs.insert(contentsOf: owed.map { [$0.id] }, at: 0)
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
        soundNextWaitingAlert()
    }

    /// One arrival per alert, in the order they came; the rest keep waiting.
    /// An expiry answered in the meantime is no longer pending.
    private func soundNextWaitingAlert() {
        while activeAudioExpiryID == nil, !waitingAudioExpiryIDs.isEmpty {
            let arrived = waitingAudioExpiryIDs.removeFirst()
            startAlert(for: pendingExpiries.filter { arrived.contains($0.id) })
        }
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
        // Deliberately an uptime deadline, which stands still during sleep.
        // A wall-clock deadline would fire the moment the Mac resumes, ahead
        // of `handleWake`, and ring a timer that the "fire timers missed
        // during sleep" setting says to discard.
        scheduler.schedule(deadline: .now() + interval, repeating: .never, leeway: .milliseconds(25))
    }

    private func persistActiveTimers() { logFailure("timers") { try persistence.save(timers) } }
    private func persistHistory() { logFailure("history") { try historyStore.save(historyEntries, now: now()) } }
    private func persistPendingExpiries() { logFailure("pending expiries") { try pendingExpiryStore.save(pendingExpiries) } }

    private func logFailure(_ store: String, _ save: () throws -> Void) {
        do {
            try save()
        } catch {
            Self.logger.error("Could not save \(store, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sortTimers() {
        timers.sort { lhs, rhs in
            if lhs.isPaused != rhs.isPaused { return !lhs.isPaused }
            if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func sortPendingExpiries() {
        pendingExpiries.sort(by: PendingExpiry.isOrderedBefore)
    }
}
