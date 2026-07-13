import AppKit
import SwiftUI

struct TimerPopoverActions {
    let cancelAll: () -> Void
    let dismissPopover: () -> Void

    func stopAll() {
        cancelAll()
        dismissPopover()
    }
}

struct RoutineLaunchAction {
    let createTimers: ([TimerTemplate]) -> Void

    func start(_ routine: TimerRoutine) {
        createTimers(routine.timerTemplates)
    }
}

enum TimerRowInlineAction: Hashable {
    case delete
    case reset
    case pause
    case resume

    var symbolName: String {
        switch self {
        case .delete: return "trash"
        case .reset: return "arrow.counterclockwise"
        case .pause: return "pause.fill"
        case .resume: return "play.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .delete: return "Delete timer"
        case .reset: return "Reset timer"
        case .pause: return "Pause timer"
        case .resume: return "Resume timer"
        }
    }
}

enum TimerRowActionPolicy {
    static func inlineActions(isPaused: Bool) -> [TimerRowInlineAction] {
        isPaused ? [.delete, .reset, .resume] : [.pause]
    }
}

enum TimerPopoverGeometry {
    /// The measured one-row fitting height before introducing a minimum.
    static let previousMinimumContentHeight: CGFloat = 199
    static let minimumHeightMultiplier: CGFloat = 1.75
    static let minimumContentHeight = ceil(
        previousMinimumContentHeight * minimumHeightMultiplier
    )
}

final class TimerPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let timerEngine: TimerEngine
    private let onOpenSettings: () -> Void
    private let onOpenHistory: () -> Void
    private let onPopoverVisibilityChanged: (Bool) -> Void
    private var hostingController: NSHostingController<TimerListView>!
    private weak var anchorView: NSView?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private lazy var actions = TimerPopoverActions(
        cancelAll: { [weak self] in self?.timerEngine.cancelAll() },
        dismissPopover: { [weak self] in self?.popover.performClose(nil) }
    )

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
        self.onOpenSettings = onOpenSettings
        self.onOpenHistory = onOpenHistory
        self.onPopoverVisibilityChanged = onPopoverVisibilityChanged
        super.init()

        popover.behavior = .transient
        popover.animates = animationsEnabled
            ?? !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        hostingController = NSHostingController(
            rootView: TimerListView(
                timerEngine: timerEngine,
                settings: settings,
                updateChecker: updateChecker ?? UpdateChecker(settings: settings),
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                },
                onOpenHistory: { [weak self] in
                    self?.openHistory()
                },
                onStopAll: { [weak self] in
                    self?.actions.stopAll()
                }
            )
        )
        popover.contentViewController = hostingController
    }

    deinit {
        stopOutsideClickMonitoring()
    }

    func toggle(relativeTo anchorView: NSView, positioningRect: NSRect) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            self.anchorView = anchorView
            onPopoverVisibilityChanged(true)
            prepareForPresentation()
            popover.show(relativeTo: positioningRect, of: anchorView, preferredEdge: .minY)
            startOutsideClickMonitoring()
        }
    }

    func updatePositioningRect(_ positioningRect: NSRect, relativeTo anchorView: NSView) {
        guard popover.isShown, self.anchorView === anchorView else { return }
        popover.positioningRect = positioningRect
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitoring()
        anchorView = nil
        onPopoverVisibilityChanged(false)
    }

    #if DEBUG
    var currentContentSize: NSSize { popover.contentSize }
    var currentFittingContentSize: NSSize { hostingController.view.fittingSize }
    var currentPositioningRect: NSRect { popover.positioningRect }
    var currentPopoverWindowFrame: NSRect? { hostingController.view.window?.frame }
    var isShownForTesting: Bool { popover.isShown }

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

    /// A custom status-item view owns its own mouse tracking loop, which means
    /// NSPopover's transient behavior is not enough to observe every outside
    /// click. Keep an explicit local and global monitor while the popover is up.
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
    let onOpenSettings: () -> Void
    let onOpenHistory: () -> Void
    let onStopAll: () -> Void

    @State private var now = Date()
    @State private var isVisible = false
    @State private var timerBeingEdited: TimerRecord?

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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

            Divider()
            footer

            if let release = updateChecker.availableRelease {
                Divider()
                updateRow(release)
            }
        }
        .frame(width: 346)
        .frame(minHeight: TimerPopoverGeometry.minimumContentHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            isVisible = true
            now = Date()
        }
        .onDisappear { isVisible = false }
        // The hosting controller outlives the popover, so the ticker keeps
        // firing after close; gating the assignment keeps the body from
        // re-rendering every second while hidden.
        .onReceive(ticker) { tick in
            if isVisible {
                now = tick
            }
        }
        .sheet(item: $timerBeingEdited) { timer in
            TimerEditorView(timer: timer) { updatedTimer in
                timerEngine.update(updatedTimer)
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
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, settings.routines.isEmpty ? 14 : 9)
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
                            RoutineLaunchAction { templates in
                                timerEngine.createTimers(templates: templates)
                            }.start(routine)
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
                        .lineLimit(1)
                    if timerEngine.pendingExpiries.count > 1 {
                        Text("1 of \(timerEngine.pendingExpiries.count)")
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
                Button("Snooze \(expiry.timer.snoozeMinutes)m") {
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
        .accessibilityLabel("\(expiry.timer.label) finished, 1 of \(timerEngine.pendingExpiries.count)")
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
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(timerEngine.timers) { timer in
                    TimerRow(
                        timer: timer,
                        now: now,
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
                        onSnooze: { timerEngine.snooze(id: timer.id) },
                        onCancel: { timerEngine.cancel(id: timer.id) }
                    )
                    if timer.id != timerEngine.timers.last?.id {
                        Divider().padding(.leading, 18)
                    }
                }
            }
        }
        .frame(maxHeight: 340)
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
                Text(timerEngine.pendingExpiries.isEmpty
                    ? "Drag the menu bar icon to start"
                    : "Finished timer needs action")
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

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quit Drag Timer")
            .help("Quit Drag Timer")

            Button(action: onOpenSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open settings")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
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

    private func durationLabel(_ minutes: Int) -> String {
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60) hr"
        }
        return "\(minutes) min"
    }

    private func quickStartLabel(_ preset: QuickStartPreset) -> String {
        let minutes = Int((preset.duration / 60).rounded())
        return preset.label.isEmpty ? durationLabel(minutes) : "\(preset.label) · \(durationLabel(minutes))"
    }

    private func quickStartAccessibilityLabel(_ preset: QuickStartPreset) -> String {
        let minutes = Int((preset.duration / 60).rounded())
        if minutes >= 60, minutes.isMultiple(of: 60) {
            let hours = minutes / 60
            return preset.label.isEmpty
                ? "a \(hours)-hour timer"
                : "\(preset.label), \(hours)-hour timer"
        }
        return preset.label.isEmpty
            ? "a \(minutes)-minute timer"
            : "\(preset.label), \(minutes)-minute timer"
    }

    private func routineAccessibilityLabel(_ routine: TimerRoutine) -> String {
        "Start \(routine.name) routine, \(routine.timers.count) \(routine.timers.count == 1 ? "timer" : "timers")"
    }

    private func displayVersion(_ tag: String) -> String {
        tag.first?.lowercased() == "v" ? String(tag.dropFirst()) : tag
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
    let onSnooze: () -> Void
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
                Text(timer.label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .overlay(alignment: .trailing) {
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .offset(x: 13)
                        }
                    }
                Text(timer.isPaused
                    ? "Paused · \(DurationText.compact(timer.remaining(at: now)))"
                    : DurationText.compact(timer.remaining(at: now)))
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
                    Button("Snooze \(timer.snoozeMinutes) min", action: onSnooze)
                    Divider()
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
                .frame(width: 20, height: 20)
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
    let onSave: (TimerRecord) -> Void

    @State private var label: String
    @State private var notify: Bool
    @State private var loop: Bool
    @State private var soundName: String
    @State private var volume: Double
    @State private var snoozeMinutes: Int
    @State private var identityColor: TimerColorToken
    @State private var identitySymbol: String

    init(timer: TimerRecord, onSave: @escaping (TimerRecord) -> Void) {
        self.timer = timer
        self.onSave = onSave
        _label = State(initialValue: timer.label)
        _notify = State(initialValue: timer.notify)
        _loop = State(initialValue: timer.loop)
        _soundName = State(initialValue: AlertSound.normalizedName(timer.soundName))
        _volume = State(initialValue: timer.volume)
        _snoozeMinutes = State(initialValue: timer.snoozeMinutes)
        _identityColor = State(initialValue: timer.resolvedIdentity.color)
        _identitySymbol = State(initialValue: timer.resolvedIdentity.symbolName)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Timer details")
                .font(.headline)
                .padding(.top, 22)

            Form {
                TextField("Label", text: $label)
                Picker("Sound", selection: $soundName) {
                    ForEach(AlertSound.allCases) { sound in
                        Text(sound.displayName).tag(sound.rawValue)
                    }
                }
                if soundName == AlertSound.systemBeep.rawValue {
                    Text("System beep uses your Mac's alert volume.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Volume")
                    Slider(value: $volume, in: 0...1)
                }
                Toggle("Loop sound", isOn: $loop)
                Toggle("Show notification", isOn: $notify)
                Stepper("Snooze for \(snoozeMinutes) min", value: $snoozeMinutes, in: 1...60)
                Picker("Color", selection: $identityColor) {
                    ForEach(TimerColorToken.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Symbol", selection: $identitySymbol) {
                    ForEach(TimerIdentity.allowedSymbols, id: \.self) { name in
                        Label(name, systemImage: name).tag(name)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save changes") {
                    var updated = timer
                    updated.label = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Timer" : label
                    updated.soundName = soundName
                    updated.volume = volume
                    updated.loop = loop
                    updated.notify = notify
                    updated.snoozeMinutes = snoozeMinutes
                    updated.identity = TimerIdentity(color: identityColor, symbolName: identitySymbol)
                    onSave(updated)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 380)
    }
}
