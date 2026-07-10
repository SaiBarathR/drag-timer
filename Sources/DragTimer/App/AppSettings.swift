import Combine
import Foundation

final class AppSettings: ObservableObject {
    private struct StoredSettings: Codable {
        var preset: FeelPreset
        var physics: DragPhysicsSettings
        var hapticsEnabled: Bool
        var snapDuringDrag: Bool
        var defaultSoundName: String
        var defaultVolume: Double
        var defaultLoop: Bool
        var defaultNotificationsEnabled: Bool
        var defaultLabel: String?
        var defaultSnoozeMinutes: Int?
        var firePastDueOnWake: Bool
    }

    private let defaults: UserDefaults
    private let storageKey = "DragTimer.AppSettings.v1"

    @Published var preset: FeelPreset { didSet { persist() } }
    @Published var physics: DragPhysicsSettings { didSet { persist() } }
    @Published var hapticsEnabled: Bool { didSet { persist() } }
    @Published var snapDuringDrag: Bool { didSet { persist() } }
    @Published var defaultSoundName: String { didSet { persist() } }
    @Published var defaultVolume: Double { didSet { persist() } }
    @Published var defaultLoop: Bool { didSet { persist() } }
    @Published var defaultNotificationsEnabled: Bool { didSet { persist() } }
    @Published var defaultLabel: String { didSet { persist() } }
    @Published var defaultSnoozeMinutes: Int { didSet { persist() } }
    @Published var firePastDueOnWake: Bool { didSet { persist() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode(StoredSettings.self, from: data) {
            preset = stored.preset
            var restoredPhysics = stored.physics.sanitized
            // Snap range was not configurable in older builds, and its fixed
            // 12-second default made haptics nearly impossible to hit.
            if restoredPhysics.snapTolerance == 12 {
                restoredPhysics.snapTolerance = 24
            }
            physics = restoredPhysics
            hapticsEnabled = stored.hapticsEnabled
            snapDuringDrag = stored.snapDuringDrag
            defaultSoundName = AlertSound.normalizedName(stored.defaultSoundName)
            defaultVolume = min(max(stored.defaultVolume, 0), 1)
            defaultLoop = stored.defaultLoop
            defaultNotificationsEnabled = stored.defaultNotificationsEnabled
            defaultLabel = stored.defaultLabel ?? "Timer"
            defaultSnoozeMinutes = max(1, stored.defaultSnoozeMinutes ?? 5)
            firePastDueOnWake = stored.firePastDueOnWake
        } else {
            preset = .snappy
            physics = .forPreset(.snappy)
            hapticsEnabled = true
            snapDuringDrag = true
            defaultSoundName = AlertSound.glass.rawValue
            defaultVolume = 0.8
            defaultLoop = false
            defaultNotificationsEnabled = true
            defaultLabel = "Timer"
            defaultSnoozeMinutes = 5
            firePastDueOnWake = true
        }
    }

    func applyPreset(_ newPreset: FeelPreset) {
        guard newPreset != .custom else { return }
        preset = newPreset
        physics = .forPreset(newPreset, basedOn: physics)
    }

    func updatePhysics(_ update: (inout DragPhysicsSettings) -> Void) {
        var copy = physics
        update(&copy)
        physics = copy.sanitized
        if preset != .custom {
            preset = .custom
        }
    }

    func defaultOptions(label: String? = nil) -> TimerOptions {
        TimerOptions(
            label: label ?? defaultLabel,
            soundName: defaultSoundName,
            volume: defaultVolume,
            loop: defaultLoop,
            notify: defaultNotificationsEnabled,
            snoozeMinutes: defaultSnoozeMinutes
        )
    }

    private func persist() {
        let stored = StoredSettings(
            preset: preset,
            physics: physics,
            hapticsEnabled: hapticsEnabled,
            snapDuringDrag: snapDuringDrag,
            defaultSoundName: defaultSoundName,
            defaultVolume: defaultVolume,
            defaultLoop: defaultLoop,
            defaultNotificationsEnabled: defaultNotificationsEnabled,
            defaultLabel: defaultLabel,
            defaultSnoozeMinutes: defaultSnoozeMinutes,
            firePastDueOnWake: firePastDueOnWake
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
