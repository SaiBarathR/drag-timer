import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    init(
        settings: AppSettings,
        updateChecker: UpdateChecker,
        notificationService: NotificationService
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Drag Timer Preferences"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 620, height: 520)
        window.setFrameAutosaveName("DragTimer.Preferences")
        window.contentViewController = NSHostingController(
            rootView: SettingsView(
                settings: settings,
                updateChecker: updateChecker,
                notificationService: notificationService
            )
                .frame(minWidth: 620, minHeight: 520)
        )
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updateChecker: UpdateChecker
    @ObservedObject var notificationService: NotificationService
    @State private var selection: SettingsPane = .general

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.symbolName)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .frame(width: 170)
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            Group {
                switch selection {
                case .general:
                    GeneralSettingsView(
                        settings: settings,
                        notificationService: notificationService
                    )
                case .presets: PresetsSettingsView(settings: settings)
                case .menuBar: MenuBarSettingsView(settings: settings)
                case .appearance: AppearanceSettingsView(settings: settings)
                case .feel: FeelSettingsView(settings: settings)
                case .updates: UpdateSettingsView(settings: settings, updateChecker: updateChecker)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(18)
        }
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case presets
    case menuBar
    case appearance
    case feel
    case updates

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "General"
        case .presets: return "Presets"
        case .menuBar: return "Menu bar"
        case .appearance: return "Appearance"
        case .feel: return "Feel"
        case .updates: return "Updates"
        }
    }
    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .presets: return "bolt.fill"
        case .menuBar: return "menubar.rectangle"
        case .appearance: return "circle.lefthalf.filled"
        case .feel: return "hand.draw"
        case .updates: return "arrow.triangle.2.circlepath"
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var notificationService: NotificationService
    @State private var launchAtLoginEnabled = LaunchAtLoginService.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        ScrollView {
            Form {
                Section("Defaults for new timers") {
                    Toggle("Ask for a label after dragging", isOn: $settings.askForLabelAfterDrag)
                    TextField("Default name", text: $settings.defaultLabel)
                    Picker("Sound", selection: $settings.defaultSoundName) {
                        ForEach(AlertSound.allCases) { Text($0.displayName).tag($0.rawValue) }
                    }
                    HStack {
                        Text("Volume")
                        Slider(value: $settings.defaultVolume, in: 0...1)
                        Text("\(Int(settings.defaultVolume * 100))%")
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    Toggle("Loop sound until stopped", isOn: $settings.defaultLoop)
                    Toggle("Show a notification", isOn: $settings.defaultNotificationsEnabled)
                    Stepper(
                        "Snooze for \(settings.defaultSnoozeMinutes) min",
                        value: $settings.defaultSnoozeMinutes,
                        in: 1...60
                    )
                }
                Section("macOS notification permission") {
                    NotificationPermissionView(notificationService: notificationService)
                }
                Section("Timer behavior") {
                    Toggle("Fire timers missed during sleep", isOn: $settings.firePastDueOnWake)
                    Toggle("Launch at login", isOn: Binding(
                        get: { launchAtLoginEnabled },
                        set: setLaunchAtLogin
                    ))
                    if let launchAtLoginError {
                        Text(launchAtLoginError).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            launchAtLoginEnabled = LaunchAtLoginService.isEnabled
            notificationService.refreshAuthorizationStatus()
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            launchAtLoginEnabled = LaunchAtLoginService.isEnabled
            launchAtLoginError = nil
        } catch {
            launchAtLoginEnabled = LaunchAtLoginService.isEnabled
            launchAtLoginError = "macOS could not update launch-at-login for this app bundle."
        }
    }
}

private struct NotificationPermissionView: View {
    @ObservedObject var notificationService: NotificationService

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if notificationService.permissionState == .checking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: symbolName)
                        .foregroundStyle(symbolColor)
                }
            }
            .frame(width: 18, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            action
        }
    }

    @ViewBuilder
    private var action: some View {
        switch notificationService.permissionState {
        case .notDetermined:
            Button("Allow Notifications") {
                notificationService.requestAuthorization()
            }
        case .denied, .authorized, .provisional:
            Button("Open Settings") {
                notificationService.openSystemSettings()
            }
        case .checking, .unavailable:
            EmptyView()
        }
    }

    private var title: String {
        switch notificationService.permissionState {
        case .unavailable: return "Packaged app required"
        case .checking: return "Checking permission…"
        case .notDetermined: return "Permission not requested"
        case .denied: return "Notifications are off"
        case .authorized: return "Notifications are allowed"
        case .provisional: return "Notifications are delivered quietly"
        }
    }

    private var detail: String {
        switch notificationService.permissionState {
        case .unavailable:
            return "Run the packaged Drag Timer.app to manage permission."
        case .checking:
            return "Reading the current macOS notification setting."
        case .notDetermined:
            return "Allow timer-finished banners with Snooze, Mark done, and Restart."
        case .denied:
            return "Enable notifications for Drag Timer in System Settings."
        case .authorized:
            return "macOS can show timer-finished banners and actions."
        case .provisional:
            return "Alerts are currently delivered quietly."
        }
    }

    private var symbolName: String {
        switch notificationService.permissionState {
        case .authorized: return "checkmark.circle.fill"
        case .provisional: return "bell.badge.fill"
        case .denied: return "bell.slash.fill"
        case .notDetermined: return "bell.badge"
        case .unavailable: return "shippingbox"
        case .checking: return "hourglass"
        }
    }

    private var symbolColor: Color {
        switch notificationService.permissionState {
        case .authorized: return .green
        case .provisional, .notDetermined: return .orange
        case .denied: return .red
        case .unavailable, .checking: return .secondary
        }
    }
}

private struct PresetsSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var editingPreset: QuickStartPreset?
    @State private var confirmsRestore = false
    @State private var limitMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick start presets").font(.headline)
                    Text("Drag rows to reorder, or use the row menu. Up to 12 presets.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    guard settings.quickStartPresets.count < AppSettings.maximumPresetCount else {
                        limitMessage = "You can keep up to 12 presets."
                        return
                    }
                    editingPreset = newPreset
                } label: { Label("Add", systemImage: "plus") }
            }

            if let limitMessage {
                Text(limitMessage).font(.caption).foregroundStyle(.red)
            }

            List {
                ForEach(settings.quickStartPresets) { preset in
                    presetRow(preset)
                        .onTapGesture(count: 2) { editingPreset = preset }
                }
                .onMove(perform: settings.movePresets)
            }
            .listStyle(.inset)

            HStack {
                Button("Restore defaults…") { confirmsRestore = true }
                Spacer()
                Text("Changes apply only to new timers.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(4)
        .sheet(item: $editingPreset) { preset in
            PresetEditorView(preset: preset) { saved in
                if settings.quickStartPresets.contains(where: { $0.id == saved.id }) {
                    settings.updatePreset(saved)
                } else if !settings.addPreset(saved) {
                    limitMessage = "You can keep up to 12 presets."
                }
            }
        }
        .confirmationDialog("Restore default presets?", isPresented: $confirmsRestore) {
            Button("Restore defaults", role: .destructive) { settings.restoreDefaultPresets() }
        } message: {
            Text("Your current preset list will be replaced.")
        }
    }

    private func presetRow(_ preset: QuickStartPreset) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            TimerIdentityBead(identity: preset.identity, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.label.isEmpty ? presetDuration(preset) : preset.label)
                    .fontWeight(.medium)
                Text(preset.label.isEmpty
                    ? alertSummary(preset)
                    : "\(presetDuration(preset)) · \(alertSummary(preset))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Edit") { editingPreset = preset }
                Button("Duplicate") {
                    if !settings.duplicatePreset(id: preset.id) {
                        limitMessage = "You can keep up to 12 presets."
                    }
                }
                Button("Move up") { settings.movePreset(id: preset.id, offset: -1) }
                Button("Move down") { settings.movePreset(id: preset.id, offset: 1) }
                Divider()
                Button("Delete", role: .destructive) { settings.removePreset(id: preset.id) }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Move up") { settings.movePreset(id: preset.id, offset: -1) }
        .accessibilityAction(named: "Move down") { settings.movePreset(id: preset.id, offset: 1) }
    }

    private var newPreset: QuickStartPreset {
        QuickStartPreset(
            duration: 5 * 60,
            alert: PresetAlertOptions(
                soundName: settings.defaultSoundName,
                volume: settings.defaultVolume,
                loop: settings.defaultLoop,
                notify: settings.defaultNotificationsEnabled,
                snoozeMinutes: settings.defaultSnoozeMinutes
            )
        )
    }

    private func alertSummary(_ preset: QuickStartPreset) -> String {
        var values = [preset.alert.soundName]
        if preset.alert.loop { values.append("loops") }
        if preset.alert.notify { values.append("notification") }
        return values.joined(separator: ", ")
    }

    private func presetDuration(_ preset: QuickStartPreset) -> String {
        let minutes = Int((preset.duration / 60).rounded())
        if minutes >= 60, minutes.isMultiple(of: 60) {
            let hours = minutes / 60
            return "\(hours) hr"
        }
        return "\(minutes) min"
    }
}

private struct PresetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let preset: QuickStartPreset
    let onSave: (QuickStartPreset) -> Void

    @State private var label: String
    @State private var minutes: Int
    @State private var soundName: String
    @State private var volume: Double
    @State private var loop: Bool
    @State private var notify: Bool
    @State private var snoozeMinutes: Int
    @State private var color: TimerColorToken
    @State private var symbolName: String

    init(preset: QuickStartPreset, onSave: @escaping (QuickStartPreset) -> Void) {
        self.preset = preset
        self.onSave = onSave
        _label = State(initialValue: preset.label)
        _minutes = State(initialValue: Int((preset.duration / 60).rounded()))
        _soundName = State(initialValue: preset.alert.soundName)
        _volume = State(initialValue: preset.alert.volume)
        _loop = State(initialValue: preset.alert.loop)
        _notify = State(initialValue: preset.alert.notify)
        _snoozeMinutes = State(initialValue: preset.alert.snoozeMinutes)
        _color = State(initialValue: preset.identity.color)
        _symbolName = State(initialValue: preset.identity.symbolName)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Quick start preset").font(.headline).padding(.top, 20)
            Form {
                TextField("Label", text: $label)
                Stepper("Duration: \(minutes) min", value: $minutes, in: 1...1_440)
                Picker("Color", selection: $color) {
                    ForEach(TimerColorToken.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Symbol", selection: $symbolName) {
                    ForEach(TimerIdentity.allowedSymbols, id: \.self) { name in
                        Label(name.replacingOccurrences(of: ".fill", with: "").capitalized, systemImage: name)
                            .tag(name)
                    }
                }
                Picker("Sound", selection: $soundName) {
                    ForEach(AlertSound.allCases) { Text($0.displayName).tag($0.rawValue) }
                }
                HStack { Text("Volume"); Slider(value: $volume, in: 0...1) }
                Toggle("Loop sound", isOn: $loop)
                Toggle("Show notification", isOn: $notify)
                Stepper("Snooze for \(snoozeMinutes) min", value: $snoozeMinutes, in: 1...60)
            }
            .padding()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    onSave(QuickStartPreset(
                        id: preset.id,
                        duration: TimeInterval(minutes * 60),
                        label: label,
                        alert: PresetAlertOptions(
                            soundName: soundName,
                            volume: volume,
                            loop: loop,
                            notify: notify,
                            snoozeMinutes: snoozeMinutes
                        ),
                        identity: TimerIdentity(color: color, symbolName: symbolName)
                    ))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 440)
    }
}

private struct MenuBarSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Display") {
                Picker("Menu bar priority", selection: $settings.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Show zero in count mode", isOn: $settings.showZeroCount)
                    .disabled(settings.menuBarDisplayMode != .count)
                if settings.menuBarDisplayMode == .pinned && settings.pinnedTimerID == nil {
                    Label("Choose Pin to menu bar from a timer's menu.", systemImage: "pin")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Ring uses the pinned timer when available, otherwise the nearest deadline.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Countdowns") {
                Picker("Countdown size", selection: $settings.countdownScale) {
                    ForEach(CountdownScale.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("High contrast", selection: $settings.contrastMode) {
                    ForEach(ContrastMode.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Urgent treatment", selection: $settings.urgentThreshold) {
                    ForEach(UrgentThreshold.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Urgency always includes an exclamation symbol and stronger weight; color is never the only cue.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("macOS accessibility") {
                Text("Drag Timer also follows Increase Contrast, Differentiate Without Color, Reduce Transparency, and Reduce Motion.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct FeelSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        ScrollView {
            Form {
                Section("Feel") {
                    Picker("Preset", selection: Binding(
                        get: { settings.preset },
                        set: { settings.applyPreset($0) }
                    )) {
                        ForEach(FeelPreset.allCases) { Text($0.displayName).tag($0) }
                    }
                    Stepper(
                        "Maximum drag duration: \(settings.maximumDragDurationHours) hr",
                        value: Binding(
                            get: { settings.maximumDragDurationHours },
                            set: settings.setMaximumDragDurationHours
                        ),
                        in: AppSettings.maximumDragDurationHoursRange
                    )
                }
                Section("Drag curve") {
                    slider("Reference drag", value: physicsBinding(\.referenceDistance), range: 240...1_100)
                    slider("Fine control", value: physicsBinding(\.gamma), range: 0.65...1.8)
                    slider("Inertia", value: physicsBinding(\.inertiaStrength), range: 0...0.8)
                    slider("Spring", value: physicsBinding(\.springStiffness), range: 80...260)
                }
                Section("Tactile feedback") {
                    Toggle("Snap to useful intervals", isOn: Binding(
                        get: { settings.physics.snappingEnabled },
                        set: { value in settings.updatePhysics { $0.snappingEnabled = value } }
                    ))
                    Toggle("Tick while passing a snap", isOn: $settings.snapDuringDrag)
                    Toggle("Use trackpad haptics", isOn: $settings.hapticsEnabled)
                    slider("Snap range", value: physicsBinding(\.snapTolerance), range: 8...60)
                }
                Button("Restore Snappy drag defaults") { settings.applyPreset(.snappy) }
            }
            .formStyle(.grouped)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack { Text(title); Slider(value: value, in: range) }
    }

    private func physicsBinding(_ keyPath: WritableKeyPath<DragPhysicsSettings, Double>) -> Binding<Double> {
        Binding(
            get: { settings.physics[keyPath: keyPath] },
            set: { value in settings.updatePhysics { $0[keyPath: keyPath] = value } }
        )
    }
}

private struct UpdateSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        Form {
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $settings.automaticallyChecksForUpdates)
                HStack {
                    Button("Check now") { Task { await updateChecker.check(manual: true) } }
                        .disabled(updateChecker.state == .checking)
                    if updateChecker.state == .checking { ProgressView().controlSize(.small) }
                    Text(statusText).font(.caption).foregroundStyle(statusColor)
                }
                if let release = updateChecker.availableRelease {
                    Button("Open \(release.tagName) on GitHub") { updateChecker.openRelease(release) }
                }
                if let lastCheck = settings.lastUpdateCheckAt {
                    Text("Last checked \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Drag Timer only opens GitHub Releases. It never downloads or installs an update itself.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        switch updateChecker.state {
        case .idle: return ""
        case .checking: return "Checking…"
        case .current: return "Drag Timer is up to date."
        case let .available(release): return "\(release.tagName) is available."
        case let .failed(message): return message
        }
    }

    private var statusColor: Color {
        if case .failed = updateChecker.state { return .red }
        return .secondary
    }
}
