import AppKit
import SwiftUI
import Combine

enum TimerRowInlineAction: Hashable {
    case delete
    case reset
    case done
    case pause
    case resume

    var symbolName: String {
        switch self {
        case .delete: return "trash"
        case .reset: return "arrow.counterclockwise"
        case .done: return "checkmark"
        case .pause: return "pause.fill"
        case .resume: return "play.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .delete: return "Delete timer"
        case .reset: return "Reset timer"
        case .done: return "Mark timer done"
        case .pause: return "Pause timer"
        case .resume: return "Resume timer"
        }
    }
}

enum TimerRowActionPolicy {
    /// Paused rows are already full, so their Mark done stays in the `…` menu.
    static func inlineActions(isPaused: Bool) -> [TimerRowInlineAction] {
        isPaused ? [.delete, .reset, .resume] : [.done, .pause]
    }
}

enum TimerListOrderPolicy {
    /// How long the pointer must be off the list before held rows move.
    static let settleDelay: TimeInterval = 0.6

    /// Rows keep the position they had in `heldOrder`, so pausing or
    /// resetting one cannot slide it out from under the pointer. Timers the
    /// held order has not seen yet follow in the engine's order.
    static func arranged(_ timers: [TimerRecord], heldOrder: [UUID]) -> [TimerRecord] {
        let heldIndex = Dictionary(
            heldOrder.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        return timers.enumerated().sorted { lhs, rhs in
            (heldIndex[lhs.element.id] ?? .max, lhs.offset) < (heldIndex[rhs.element.id] ?? .max, rhs.offset)
        }.map(\.element)
    }

    enum Settle: Equatable {
        case hold
        case afterDelay
        case immediately
    }

    /// What a change in the engine's timer ids does to the held order. A new
    /// timer lands in its sorted place right away; a row that was only acted
    /// on waits, in case the pointer is on its way back.
    static func settle(from previous: [UUID], to current: [UUID], isPointerOverList: Bool) -> Settle {
        if isPointerOverList { return .hold }
        return Set(current).isSubset(of: previous) ? .afterDelay : .immediately
    }
}

enum TimerPopoverGeometry {
    static let minimumContentHeight: CGFloat = 349
}

/// The "Other length…" entry. It lives outside the SwiftUI view because the
/// view outlives each presentation of the popover: left expanded, the field
/// would take keyboard focus on the next open and swallow the Return that is
/// meant for the expiry card.
final class TypedLengthEntry: ObservableObject {
    @Published var isOpen = false
    @Published var text = ""

    func reset() {
        isOpen = false
        text = ""
    }
}

final class TimerPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let timerEngine: TimerEngine
    private let settings: AppSettings
    private let updateChecker: UpdateChecker
    private let onOpenSettings: () -> Void
    private let onOpenHistory: () -> Void
    private let onPopoverVisibilityChanged: (Bool) -> Void
    private let typedLength = TypedLengthEntry()
    private var hostingController: NSHostingController<TimerListView>!
    /// The tallest the content may be: what fits below the menu bar on the
    /// screen the popover opened on. Past that the timer list scrolls.
    private var maximumContentHeight: CGFloat = .infinity {
        didSet {
            // Handed over as a new root view, which the next layout already
            // uses; a published value would arrive a turn after the popover
            // had been measured and shown.
            guard maximumContentHeight != oldValue else { return }
            hostingController.rootView = makeRootView()
        }
    }
    /// Room for the popover's arrow and a little air above the screen's edge.
    private static let screenMargin: CGFloat = 24
    private weak var anchorView: NSView?
    /// Where on the screen the popover was attached when it opened.
    private var anchorScreenRect: NSRect?
    private var anchorWindowObservers: [NSObjectProtocol] = []
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    init(
        timerEngine: TimerEngine,
        settings: AppSettings,
        updateChecker: UpdateChecker? = nil,
        onOpenSettings: @escaping () -> Void,
        onOpenHistory: @escaping () -> Void = {},
        onPopoverVisibilityChanged: @escaping (Bool) -> Void = { _ in },
        animationsEnabled: Bool? = nil
    ) {
        self.timerEngine = timerEngine
        self.settings = settings
        self.updateChecker = updateChecker ?? UpdateChecker(settings: settings)
        self.onOpenSettings = onOpenSettings
        self.onOpenHistory = onOpenHistory
        self.onPopoverVisibilityChanged = onPopoverVisibilityChanged
        super.init()

        popover.behavior = .transient
        popover.animates = animationsEnabled
            ?? !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        hostingController = NSHostingController(rootView: makeRootView())
        // The popover follows its content for as long as it is open. Sized
        // only when shown, it squeezed the timer list to nothing, or pushed
        // the presets and the footer out of view, once a finished card, a
        // new timer or the Undo offer arrived in a popover that had opened
        // with less in it.
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
    }

    deinit {
        stopOutsideClickMonitoring()
        releaseAnchor()
    }

    private func makeRootView() -> TimerListView {
        TimerListView(
            timerEngine: timerEngine,
            settings: settings,
            updateChecker: updateChecker,
            typedLength: typedLength,
            maximumHeight: maximumContentHeight,
            onOpenSettings: { [weak self] in
                self?.openSettings()
            },
            onOpenHistory: { [weak self] in
                self?.openHistory()
            },
            // The popover stays open: the offer to undo is in it.
            onStopAll: { [weak self] in
                self?.timerEngine.cancelAll()
            }
        )
    }

    func toggle(relativeTo anchorView: NSView, positioningRect: NSRect) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            self.anchorView = anchorView
            onPopoverVisibilityChanged(true)
            if let screen = anchorView.window?.screen ?? NSScreen.main {
                maximumContentHeight = max(
                    TimerPopoverGeometry.minimumContentHeight,
                    screen.visibleFrame.height - Self.screenMargin
                )
            }
            prepareForPresentation()
            popover.show(relativeTo: positioningRect, of: anchorView, preferredEdge: .minY)
            holdAnchor(at: positioningRect, in: anchorView)
            startOutsideClickMonitoring()
        }
    }

    /// The status item reports that its icon has moved inside it.
    func anchorDidChange(in anchorView: NSView) {
        guard self.anchorView === anchorView else { return }
        stayWhereOpened()
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitoring()
        releaseAnchor()
        anchorView = nil
        typedLength.reset()
        onPopoverVisibilityChanged(false)
    }

    #if DEBUG
    var currentContentSize: NSSize { popover.contentSize }
    var currentFittingContentSize: NSSize { hostingController.view.fittingSize }
    var currentPositioningRect: NSRect { popover.positioningRect }
    var currentPopoverWindowFrame: NSRect? { hostingController.view.window?.frame }
    var isShownForTesting: Bool { popover.isShown }
    var typedLengthForTesting: TypedLengthEntry { typedLength }

    var maximumContentHeightForTesting: CGFloat { maximumContentHeight }
    static var screenMarginForTesting: CGFloat { screenMargin }

    func setMaximumContentHeightForTesting(_ height: CGFloat) {
        maximumContentHeight = height
    }

    func prepareForPresentationForTesting() {
        prepareForPresentation()
    }

    func closeForTesting() {
        popover.close()
    }
    #endif

    private func openSettings() {
        popover.performClose(nil)
        onOpenSettings()
    }

    private func openHistory() {
        popover.performClose(nil)
        onOpenHistory()
    }

    private func prepareForPresentation() {
        let contentView = hostingController.view
        contentView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()
        let fittingSize = contentView.fittingSize
        guard fittingSize.width.isFinite,
              fittingSize.height.isFinite,
              fittingSize.width > 0,
              fittingSize.height > 0 else {
            return
        }
        popover.contentSize = fittingSize
    }

    /// The status item grows to its left when a countdown or a finished
    /// timer's count-up appears in it, and the icon goes with it. A popover
    /// that followed would jump sideways under the pointer, Timer details
    /// included, so it stays attached to the spot it opened at. The item's
    /// window moves some time after the item asks for its new width, and
    /// the popover places itself afresh whenever it resizes; hence both the
    /// window's notifications and the screen rectangle kept here.
    private func holdAnchor(at positioningRect: NSRect, in anchorView: NSView) {
        releaseAnchor()
        guard let window = anchorView.window else { return }
        anchorScreenRect = window.convertToScreen(anchorView.convert(positioningRect, to: nil))
        anchorWindowObservers = [NSWindow.didMoveNotification, NSWindow.didResizeNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: nil) { [weak self] _ in
                self?.stayWhereOpened()
            }
        }
    }

    private func releaseAnchor() {
        anchorWindowObservers.forEach(NotificationCenter.default.removeObserver)
        anchorWindowObservers = []
        anchorScreenRect = nil
    }

    private func stayWhereOpened() {
        guard popover.isShown,
              let anchorView,
              let window = anchorView.window,
              let anchorScreenRect else {
            return
        }
        let positioningRect = anchorView.convert(window.convertFromScreen(anchorScreenRect), from: nil)
        if positioningRect != popover.positioningRect {
            popover.positioningRect = positioningRect
        }
    }

    /// The popover is anchored to a custom status-item view, where NSPopover's
    /// transient behavior does not observe every outside click. Keep an
    /// explicit local and global monitor while the popover is up.
    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()

        let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.closeIfNeeded(for: NSEvent.mouseLocation)
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closeIfNeeded(for: NSEvent.mouseLocation)
            }
        }
    }

    private func stopOutsideClickMonitoring() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private func closeIfNeeded(for screenPoint: CGPoint) {
        guard popover.isShown,
              !isPointInsidePopover(screenPoint),
              !isPointInsideAnchor(screenPoint) else {
            return
        }
        popover.performClose(nil)
    }

    private func isPointInsidePopover(_ screenPoint: CGPoint) -> Bool {
        guard let contentWindow = popover.contentViewController?.view.window else { return false }
        // The timer editor is presented as a sheet attached to the popover's
        // window; clicks inside it (or any child window, such as an open
        // menu) must not count as "outside".
        var windows: [NSWindow] = [contentWindow]
        windows.append(contentsOf: contentWindow.sheets)
        if let attachedSheet = contentWindow.attachedSheet {
            windows.append(attachedSheet)
        }
        windows.append(contentsOf: contentWindow.childWindows ?? [])
        return windows.contains { $0.frame.insetBy(dx: -2, dy: -2).contains(screenPoint) }
    }

    private func isPointInsideAnchor(_ screenPoint: CGPoint) -> Bool {
        guard let anchorView, let anchorWindow = anchorView.window else { return false }
        let anchorRect = anchorView.convert(anchorView.bounds, to: nil)
        let screenRect = anchorWindow.convertToScreen(anchorRect)
        return screenRect.insetBy(dx: -2, dy: -2).contains(screenPoint)
    }
}

private struct TimerListView: View {
    @ObservedObject var timerEngine: TimerEngine
    @ObservedObject var settings: AppSettings
    @ObservedObject var updateChecker: UpdateChecker
    @ObservedObject var typedLength: TypedLengthEntry
    let maximumHeight: CGFloat
    let onOpenSettings: () -> Void
    let onOpenHistory: () -> Void
    let onStopAll: () -> Void

    @State private var timerBeingEdited: TimerRecord?
    @State private var contentHeight: CGFloat = 0
    /// The height held while Timer details is open. The sheet is attached to
    /// the popover, so a popover that resized behind it would move the sheet
    /// and its buttons under the pointer.
    @State private var heightUnderDetails: CGFloat?
    @State private var heldOrder: [UUID] = []
    @State private var isPointerOverList = false
    @State private var pendingSettle: DispatchWorkItem?
    @FocusState private var customDurationFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            quickStart

            if !settings.routines.isEmpty {
                routineLaunchStrip
            }

            if let expiry = timerEngine.currentExpiry {
                expiryCard(for: expiry)
            }

            mainContent
                .frame(
                    maxHeight: .infinity,
                    alignment: timerEngine.timers.isEmpty ? .center : .top
                )

            if let removal = timerEngine.undoableRemoval {
                Divider()
                undoRow(removal)
            }

            Divider()
            footer

            if let release = updateChecker.availableRelease {
                Divider()
                updateRow(release)
            }
        }
        .frame(width: 346)
        .frame(
            minHeight: heightUnderDetails ?? TimerPopoverGeometry.minimumContentHeight,
            maxHeight: heightUnderDetails ?? maximumHeight
        )
        .background(GeometryReader { proxy in
            Color.clear.preference(key: PopoverContentHeightKey.self, value: proxy.size.height)
        })
        .onPreferenceChange(PopoverContentHeightKey.self) { contentHeight = $0 }
        .onChange(of: timerBeingEdited?.id) { _, edited in
            heightUnderDetails = edited == nil || contentHeight <= 0 ? nil : contentHeight
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            heldOrder = timerEngine.timers.map(\.id)
        }
        .onDisappear {
            isPointerOverList = false
            pendingSettle?.cancel()
        }
        .onChange(of: timerEngine.undoableRemoval?.id) { _, offered in
            // The button that was pressed has gone and the offer appears
            // elsewhere, for ten seconds; VoiceOver has to be told.
            if offered != nil, let removal = timerEngine.undoableRemoval {
                AccessibilityNotification.Announcement("\(removal.summary). Undo is available.").post()
            }
        }
        .onChange(of: timerEngine.timers.map(\.id)) { previous, current in
            // A timer that rings or is removed while its details are open
            // has nothing left to edit; saving would be dropped unseen.
            if let edited = timerBeingEdited, !current.contains(edited.id) {
                timerBeingEdited = nil
            }
            switch TimerListOrderPolicy.settle(
                from: previous,
                to: current,
                isPointerOverList: isPointerOverList
            ) {
            case .hold: break
            case .afterDelay: scheduleSettle()
            case .immediately: settleOrder()
            }
        }
        .sheet(item: $timerBeingEdited) { timer in
            TimerEditorView(timer: timer) { updatedTimer, newTimeLeft in
                timerEngine.update(updatedTimer)
                if let newTimeLeft {
                    timerEngine.setRemaining(id: updatedTimer.id, to: newTimeLeft)
                }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if timerEngine.timers.isEmpty {
            emptyState
        } else {
            timerList
        }
    }

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Quick start")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            LazyVGrid(columns: quickStartColumns, spacing: 7) {
                ForEach(settings.quickStartPresets) { preset in
                    Button {
                        timerEngine.createTimer(template: preset.timerTemplate())
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: preset.identity.symbolName)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(preset.identity.color.color)
                            Text(quickStartLabel(preset))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Start \(quickStartAccessibilityLabel(preset))")
                    .help(quickStartAccessibilityLabel(preset))
                }
            }

            customDurationEntry
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, settings.routines.isEmpty ? 14 : 9)
    }

    /// Collapsed by default so opening the popover never puts keyboard focus
    /// in a text field; Return must keep reaching the expiry card.
    @ViewBuilder
    private var customDurationEntry: some View {
        if typedLength.isOpen {
            HStack(spacing: 7) {
                TextField("25m, 90s, 1:30, @3:30pm", text: $typedLength.text)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .focused($customDurationFocused)
                    .onSubmit(startCustomDuration)
                    .onExitCommand { typedLength.isOpen = false }
                    // Focus cannot be requested until the field is in the view tree.
                    .onAppear { customDurationFocused = true }
                    .accessibilityLabel("Timer length or time of day")
                // Names what it read, so "1:30" is seen to mean an hour and a
                // half, and "@4" to mean 4 PM, before the timer starts.
                // Read again each minute: "@3:30pm" means tomorrow once
                // 3:30 has gone by with the field still open.
                TimelineView(.everyMinute) { _ in
                    let entry = DurationInput.parseEntry(typedLength.text)
                    Button(entry?.startTitle() ?? "Start", action: startCustomDuration)
                        .controlSize(.small)
                        .disabled(entry == nil)
                }
            }
        } else {
            Button {
                typedLength.isOpen = true
            } label: {
                Label("Other length or time…", systemImage: "keyboard")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityHint("Type a timer length such as 25m or 90s, or a time such as @3:30pm")
        }
    }

    private func startCustomDuration() {
        // Read again now: a time of day is further away or nearer than it
        // was when the title was drawn.
        let duration: TimeInterval
        switch DurationInput.parseEntry(typedLength.text) {
        case let .length(length)?: duration = length
        // Rounded up, so it never rings before the clock reads that time.
        case let .clockTime(date)?: duration = date.timeIntervalSinceNow.rounded(.up)
        case nil: return
        }
        timerEngine.createTimer(duration: duration, options: settings.defaultOptions())
        typedLength.text = ""
        typedLength.isOpen = false
    }

    private var routineLaunchStrip: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Routines")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(settings.routines) { routine in
                        Button {
                            timerEngine.createTimers(templates: routine.timerTemplates)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(routine.name)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .lineLimit(1)
                                    Text("\(routine.timers.count) \(routine.timers.count == 1 ? "timer" : "timers")")
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 2)
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 9)
                            .frame(width: 150, height: 38)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel(routineAccessibilityLabel(routine))
                        .help(routineAccessibilityLabel(routine))
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private func expiryCard(for expiry: PendingExpiry) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                TimerIdentityBead(identity: expiry.timer.resolvedIdentity, size: 26, urgent: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(expiry.timer.label) finished")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    // Re-read on each whole minute since it finished, and
                    // only while the popover is on screen.
                    TimelineView(.periodic(from: expiry.dueAt, by: 60)) { context in
                        Text(expiryCaption(for: expiry, at: context.date))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    timerEngine.silenceExpiryAudio()
                } label: { Image(systemName: "speaker.slash.fill") }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop sound")
                .help("Stop sound")
            }
            HStack(spacing: 7) {
                Button("Snooze \(expiry.timer.snoozeMinutes) min") {
                    timerEngine.snoozeExpiry(id: expiry.id)
                }
                Button("Restart") {
                    timerEngine.restartExpiry(id: expiry.id)
                }
                Button("Mark done") {
                    timerEngine.markExpiryDone(id: expiry.id)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(Color.red.opacity(TimerAppearancePolicy.highContrast(settings: settings) ? 0.16 : 0.08))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(timerEngine.pendingExpiries.count > 1
            ? "\(expiry.timer.label) finished, 1 of \(timerEngine.pendingExpiries.count)"
            : "\(expiry.timer.label) finished")
    }

    private func expiryCaption(for expiry: PendingExpiry, at date: Date) -> String {
        let ago = MenuBarCountdown.finishedAgoText(since: expiry.dueAt, at: date)
        let caption = ago.prefix(1).uppercased() + ago.dropFirst()
        let count = timerEngine.pendingExpiries.count
        return count > 1 ? "\(caption) · 1 of \(count)" : caption
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.draw")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("Or pull any duration")
                .font(.system(size: 14, weight: .medium))
            Text("Drag from the menu-bar icon when a preset does not fit.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 22)
    }

    private var timerList: some View {
        let rows = TimerListOrderPolicy.arranged(timerEngine.timers, heldOrder: heldOrder)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows) { timer in
                    // Each running row ticks on its own timer's whole-second
                    // boundaries, and only while the popover is on screen.
                    TimelineView(.periodic(
                        from: CountdownClock.tickAnchor(for: timer),
                        by: timer.isPaused ? 3_600 : 1
                    )) { context in
                    TimerRow(
                        timer: timer,
                        now: context.date,
                        countdownScale: settings.countdownScale,
                        urgentThreshold: settings.urgentThreshold,
                        highContrast: TimerAppearancePolicy.highContrast(settings: settings),
                        isPinned: settings.pinnedTimerID == timer.id,
                        onEdit: { timerBeingEdited = timer },
                        onPin: {
                            settings.pinnedTimerID = settings.pinnedTimerID == timer.id ? nil : timer.id
                        },
                        onPauseResume: {
                            timer.isPaused
                                ? timerEngine.resume(id: timer.id)
                                : timerEngine.pause(id: timer.id)
                        },
                        onReset: { timerEngine.reset(id: timer.id) },
                        onAdjustTime: { timerEngine.adjustTime(id: timer.id, by: $0) },
                        onDone: { timerEngine.markDone(id: timer.id) },
                        onCancel: { timerEngine.cancel(id: timer.id) }
                    )
                    }
                    if timer.id != rows.last?.id {
                        Divider().padding(.leading, 18)
                    }
                }
            }
        }
        .frame(maxHeight: 340)
        .onHover { hovering in
            isPointerOverList = hovering
            if hovering {
                pendingSettle?.cancel()
            } else {
                scheduleSettle()
            }
        }
        .onDisappear { isPointerOverList = false }
    }

    private func scheduleSettle() {
        pendingSettle?.cancel()
        let settle = DispatchWorkItem {
            guard !isPointerOverList else { return }
            settleOrder()
        }
        pendingSettle = settle
        DispatchQueue.main.asyncAfter(
            deadline: .now() + TimerListOrderPolicy.settleDelay,
            execute: settle
        )
    }

    private func settleOrder() {
        pendingSettle?.cancel()
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            heldOrder = timerEngine.timers.map(\.id)
        }
    }

    private var footer: some View {
        HStack {
            if !timerEngine.timers.isEmpty {
                Button("Stop all") {
                    onStopAll()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .accessibilityHint("Cancels every timer and stops any ringing sound")

                Text(timerSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // The empty state above already explains the drag.
                Text(timerEngine.pendingExpiries.isEmpty ? "No timers" : "Finished timer needs action")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onOpenHistory) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open timer history")
            .help("History")

            Button(action: onOpenSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open settings")
            .help("Settings")

            // Quit is one step away rather than a bare icon beside Settings.
            Menu {
                Button("Quit Drag Timer") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
            .help("More")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func undoRow(_ removal: TimerRemoval) -> some View {
        HStack(spacing: 8) {
            // Decoration; VoiceOver would read the symbol as a second "Undo".
            Image(systemName: "arrow.uturn.backward.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(removal.summary)
                .font(.caption)
                .lineLimit(1)
                .help(removal.summary)
            Spacer()
            Button("Undo") { timerEngine.undoLastRemoval() }
                .controlSize(.small)
                // Command-Z belongs to the text while a length is being typed
                // or a timer's details are open.
                .keyboardShortcut(
                    typedLength.isOpen || timerBeingEdited != nil
                        ? nil
                        : KeyboardShortcut("z", modifiers: .command)
                )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }

    private func updateRow(_ release: GitHubRelease) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
            Text("Version \(displayVersion(release.tagName)) available")
                .font(.caption)
            Spacer()
            Button("Open") { updateChecker.openRelease(release) }
                .controlSize(.small)
            Button {
                updateChecker.dismissAvailableRelease()
            } label: { Image(systemName: "xmark") }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss update notice")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }

    private var timerSummary: String {
        let paused = timerEngine.timers.filter(\.isPaused).count
        let running = timerEngine.timers.count - paused
        if running == 0 && paused == 0 { return "No timers running" }
        if paused == 0 { return "\(running) running" }
        if running == 0 { return "\(paused) paused" }
        return "\(running) running, \(paused) paused"
    }

    private var quickStartColumns: [GridItem] {
        let labeled = settings.quickStartPresets.contains { !$0.label.isEmpty }
        let count = labeled || settings.countdownScale != .standard ? 2 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 7), count: count)
    }

    private func quickStartLabel(_ preset: QuickStartPreset) -> String {
        let duration = DurationText.planned(preset.duration)
        return preset.label.isEmpty ? duration : "\(preset.label) · \(duration)"
    }

    private func quickStartAccessibilityLabel(_ preset: QuickStartPreset) -> String {
        let length = DurationText.spoken(preset.duration)
        return preset.label.isEmpty ? "a \(length) timer" : "\(preset.label), \(length) timer"
    }

    private func routineAccessibilityLabel(_ routine: TimerRoutine) -> String {
        "Start \(routine.name) routine, \(routine.timers.count) \(routine.timers.count == 1 ? "timer" : "timers")"
    }

    private func displayVersion(_ tag: String) -> String {
        tag.first?.lowercased() == "v" ? String(tag.dropFirst()) : tag
    }
}

private struct PopoverContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TimerRow: View {
    let timer: TimerRecord
    let now: Date
    let countdownScale: CountdownScale
    let urgentThreshold: UrgentThreshold
    let highContrast: Bool
    let isPinned: Bool
    let onEdit: () -> Void
    let onPin: () -> Void
    let onPauseResume: () -> Void
    let onReset: () -> Void
    let onAdjustTime: (TimeInterval) -> Void
    let onDone: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(timer.resolvedIdentity.color.color.opacity(0.25), lineWidth: highContrast ? 3 : 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(urgent ? Color.red : (timer.isPaused ? Color.secondary : timer.resolvedIdentity.color.color),
                            style: StrokeStyle(lineWidth: highContrast ? 3 : 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if timer.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: urgent ? "exclamationmark" : timer.resolvedIdentity.symbolName)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(urgent ? Color.red : timer.resolvedIdentity.color.color)
                }
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(timer.label)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .help(timer.label)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Pinned to menu bar")
                    }
                }
                Text(timer.isPaused
                    ? "Paused · \(MenuBarCountdown.text(for: timer, at: now))"
                    : MenuBarCountdown.text(for: timer, at: now))
                    .font(.system(
                        size: 12 * countdownScale.factor,
                        weight: urgent ? .semibold : .regular,
                        design: .monospaced
                    ))
                    .foregroundStyle(urgent ? Color.red : Color.secondary)
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                ForEach(TimerRowActionPolicy.inlineActions(isPaused: timer.isPaused), id: \.self) { action in
                    inlineButton(for: action)
                }

                Menu {
                    Button(isPinned ? "Unpin from menu bar" : "Pin to menu bar", action: onPin)
                    Divider()
                    Button("Edit timer", action: onEdit)
                    Button(timer.isPaused ? "Resume timer" : "Pause timer", action: onPauseResume)
                    Button("Reset timer", action: onReset)
                    Divider()
                    Button("Add 1 min") { onAdjustTime(60) }
                    if timer.snoozeMinutes != 1 {
                        Button("Add \(timer.snoozeMinutes) min") {
                            onAdjustTime(TimeInterval(timer.snoozeMinutes * 60))
                        }
                    }
                    // The engine needs a second left after the minute
                    // comes off. For a running timer `now` is the row's
                    // last whole-second tick, so up to a second more has
                    // gone by; a paused timer's time left is exact.
                    Button("Subtract 1 min") { onAdjustTime(-60) }
                        .disabled(timer.remaining(at: now) <= (timer.isPaused ? 60 : 61))
                    Divider()
                    Button("Mark done", action: onDone)
                    Button("Cancel timer", role: .destructive, action: onCancel)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func inlineButton(for action: TimerRowInlineAction) -> some View {
        Button(role: action == .delete ? .destructive : nil) {
            perform(action)
        } label: {
            Image(systemName: action.symbolName)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(action == .delete ? Color.red : Color.primary)
        .accessibilityLabel(action.accessibilityLabel)
        .help(action.accessibilityLabel)
    }

    private func perform(_ action: TimerRowInlineAction) {
        switch action {
        case .delete:
            onCancel()
        case .reset:
            onReset()
        case .done:
            onDone()
        case .pause, .resume:
            onPauseResume()
        }
    }

    private var progress: CGFloat {
        CGFloat(timer.progress(at: now))
    }

    private var urgent: Bool {
        TimerAppearancePolicy.isUrgent(timer, at: now, threshold: urgentThreshold)
    }
}

private struct TimerEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let timer: TimerRecord
    /// The second value is a new time left, or nil when it was not edited:
    /// the countdown kept running while the sheet was open, and saving a
    /// new name must not wind it back.
    let onSave: (TimerRecord, TimeInterval?) -> Void

    @State private var options: TimerOptions
    @State private var timeLeftText: String
    /// State, not a constant: the list behind the sheet rebuilds this view
    /// whenever the engine publishes, and a constant would be read from the
    /// clock again each time and no longer match the untouched field.
    @State private var openedTimeLeftText: String

    init(timer: TimerRecord, onSave: @escaping (TimerRecord, TimeInterval?) -> Void) {
        self.timer = timer
        self.onSave = onSave
        let timeLeftText = DurationField.text(for: timer.remaining().rounded(.up))
        _options = State(initialValue: timer.options)
        _timeLeftText = State(initialValue: timeLeftText)
        _openedTimeLeftText = State(initialValue: timeLeftText)
    }

    private var editedTimeLeft: TimeInterval? {
        timeLeftText == openedTimeLeftText ? nil : DurationInput.parse(timeLeftText)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Timer details")
                .font(.headline)
                .padding(.top, 22)

            Form {
                // Reserved rather than growing: the sheet keeps the size it
                // was presented with, so a field that grows while typing
                // would hide every line but the last.
                TextField("Label", text: $options.label, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                DurationField(title: "Time left", text: $timeLeftText, unedited: openedTimeLeftText)
                TimerOptionFields(options: $options)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save changes") {
                    var updated = timer
                    updated.apply(options)
                    onSave(updated, editedTimeLeft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                // An untouched field never blocks saving the other fields.
                .disabled(timeLeftText != openedTimeLeftText && DurationInput.parse(timeLeftText) == nil)
            }
            .padding(20)
        }
        .frame(width: 380)
    }
}
