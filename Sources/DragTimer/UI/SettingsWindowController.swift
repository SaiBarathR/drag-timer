import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    init(settings: AppSettings) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Drag Timer Preferences"
        window.titleVisibility = .visible
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 500, height: 560)
        window.setFrameAutosaveName("DragTimer.Preferences")
        window.contentViewController = NSHostingController(
            rootView: SettingsView(settings: settings)
                .frame(minWidth: 500, minHeight: 560)
        )
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var launchAtLoginEnabled = LaunchAtLoginService.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        ScrollView {
            Form {
                Section("Defaults for new timers") {
                    TextField("Default name", text: $settings.defaultLabel)
                    Picker("Sound", selection: $settings.defaultSoundName) {
                        ForEach(AlertSound.allCases) { sound in
                            Text(sound.displayName).tag(sound.rawValue)
                        }
                    }
                    if settings.defaultSoundName == AlertSound.systemBeep.rawValue {
                        Text("System beep uses your Mac's alert volume.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Volume")
                        Slider(value: $settings.defaultVolume, in: 0...1)
                        Text("\(Int(settings.defaultVolume * 100))%")
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                    Toggle("Loop sound until stopped", isOn: $settings.defaultLoop)
                    Toggle("Show a notification", isOn: $settings.defaultNotificationsEnabled)
                    Stepper(
                        "Snooze for \(settings.defaultSnoozeMinutes) min",
                        value: $settings.defaultSnoozeMinutes,
                        in: 1...60
                    )
                    Text("These choices are applied only to timers you create after changing them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Feel") {
                    Picker("Preset", selection: Binding(
                        get: { settings.preset },
                        set: { settings.applyPreset($0) }
                    )) {
                        ForEach(FeelPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    Text("Choose the character of the release, then fine-tune it below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Drag curve") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Reference drag")
                            Spacer()
                            Text("\(Int(settings.physics.referenceDistance)) pt")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: physicsBinding(\.referenceDistance), in: 240...1_100, step: 10)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Fine control")
                            Spacer()
                            Text(String(format: "%.2f", settings.physics.gamma))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: physicsBinding(\.gamma), in: 1.0...2.5, step: 0.05)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Throw strength")
                            Spacer()
                            Text(String(format: "%.2f", settings.physics.inertiaStrength))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: physicsBinding(\.inertiaStrength), in: 0...0.25, step: 0.01)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Spring stiffness")
                            Spacer()
                            Text("\(Int(settings.physics.springStiffness))")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: physicsBinding(\.springStiffness), in: 80...260, step: 5)
                    }
                }

                Section("Tactile feedback") {
                    Toggle("Snap to useful intervals", isOn: snappingBinding)
                    Toggle("Tick while passing a snap", isOn: $settings.snapDuringDrag)
                        .disabled(!settings.physics.snappingEnabled)
                    Toggle("Use trackpad haptics", isOn: $settings.hapticsEnabled)
                        .disabled(!settings.physics.snappingEnabled)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Snap range")
                            Spacer()
                            Text("\(Int(settings.physics.snapTolerance)) sec")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: physicsBinding(\.snapTolerance), in: 8...60, step: 2)
                    }
                    .disabled(!settings.physics.snappingEnabled)
                    Text("A haptic tick is sent whenever the drag enters a snapped duration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Timer behavior") {
                    Toggle("Fire timers missed during sleep", isOn: $settings.firePastDueOnWake)
                    Toggle("Launch at login", isOn: Binding(
                        get: { launchAtLoginEnabled },
                        set: { setLaunchAtLogin($0) }
                    ))
                    if let launchAtLoginError {
                        Text(launchAtLoginError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                        ? "Reduce Motion is on; inertia and spring settling are shortened automatically."
                        : "Reduce Motion is off. The release uses the selected inertia and spring.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Restore Snappy drag defaults") {
                        settings.applyPreset(.snappy)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            launchAtLoginEnabled = LaunchAtLoginService.isEnabled
        }
    }

    private var snappingBinding: Binding<Bool> {
        Binding(
            get: { settings.physics.snappingEnabled },
            set: { value in settings.updatePhysics { $0.snappingEnabled = value } }
        )
    }

    private func physicsBinding(_ keyPath: WritableKeyPath<DragPhysicsSettings, Double>) -> Binding<Double> {
        Binding(
            get: { settings.physics[keyPath: keyPath] },
            set: { value in
                settings.updatePhysics { physics in
                    physics[keyPath: keyPath] = value
                }
            }
        )
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
