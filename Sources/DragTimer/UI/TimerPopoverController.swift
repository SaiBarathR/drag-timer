import AppKit
import SwiftUI

final class TimerPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let onOpenSettings: () -> Void
    private weak var anchorView: NSView?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    init(
        timerEngine: TimerEngine,
        settings: AppSettings,
        onOpenSettings: @escaping () -> Void
    ) {
        self.onOpenSettings = onOpenSettings
        super.init()

        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: TimerListView(
                timerEngine: timerEngine,
                settings: settings,
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                }
            )
        )
    }

    deinit {
        stopOutsideClickMonitoring()
    }

    func toggle(relativeTo anchorView: NSView) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            self.anchorView = anchorView
            popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
            startOutsideClickMonitoring()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitoring()
        anchorView = nil
    }

    private func openSettings() {
        popover.performClose(nil)
        onOpenSettings()
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
        return contentWindow.frame.insetBy(dx: -2, dy: -2).contains(screenPoint)
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
    let onOpenSettings: () -> Void

    @State private var now = Date()
    @State private var timerBeingEdited: TimerRecord?

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header

            if let activeAlert = timerEngine.activeAlert {
                alertBanner(for: activeAlert)
            }

            if timerEngine.timers.isEmpty {
                emptyState
            } else {
                timerList
            }

            Divider()
            footer
        }
        .frame(width: 346)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(ticker) { now = $0 }
        .sheet(item: $timerBeingEdited) { timer in
            TimerEditorView(timer: timer) { updatedTimer in
                timerEngine.update(updatedTimer)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Drag Timer")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(timerEngine.timers.isEmpty ? "No timers running" : "\(timerEngine.timers.count) running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func alertBanner(for timer: TimerRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.fill")
                .foregroundStyle(.red)
            Text("\(timer.label) is ringing")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer()
            Button("Stop sound") {
                timerEngine.stopActiveAlert()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.08))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.draw")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("Pull time from the menu bar")
                .font(.system(size: 14, weight: .medium))
            Text("Press the timer icon and drag. Distance sets time; a fast release adds momentum.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 34)
    }

    private var timerList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(timerEngine.timers) { timer in
                    TimerRow(
                        timer: timer,
                        now: now,
                        onEdit: { timerBeingEdited = timer },
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
            Text("Drag the menu bar icon to start")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
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
}

private struct TimerRow: View {
    let timer: TimerRecord
    let now: Date
    let onEdit: () -> Void
    let onSnooze: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(timer.label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(DurationText.compact(timer.remaining(at: now)))
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Menu {
                Button("Edit timer", action: onEdit)
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
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var progress: CGFloat {
        let total = max(1, timer.fireDate.timeIntervalSince(timer.createdAt))
        let elapsed = max(0, min(total, now.timeIntervalSince(timer.createdAt)))
        return CGFloat(elapsed / total)
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

    init(timer: TimerRecord, onSave: @escaping (TimerRecord) -> Void) {
        self.timer = timer
        self.onSave = onSave
        _label = State(initialValue: timer.label)
        _notify = State(initialValue: timer.notify)
        _loop = State(initialValue: timer.loop)
        _soundName = State(initialValue: AlertSound.normalizedName(timer.soundName))
        _volume = State(initialValue: timer.volume)
        _snoozeMinutes = State(initialValue: timer.snoozeMinutes)
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
