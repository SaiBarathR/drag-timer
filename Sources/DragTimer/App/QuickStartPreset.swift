import Foundation

struct PresetAlertOptions: Codable, Equatable {
    var soundName: String
    var volume: Double
    var loop: Bool
    var notify: Bool
    var snoozeMinutes: Int

    init(
        soundName: String = AlertSound.glass.rawValue,
        volume: Double = 0.8,
        loop: Bool = false,
        notify: Bool = true,
        snoozeMinutes: Int = 5
    ) {
        self.soundName = AlertSound.normalizedName(soundName)
        self.volume = min(max(volume, 0), 1)
        self.loop = loop
        self.notify = notify
        self.snoozeMinutes = min(max(snoozeMinutes, 1), 60)
    }
}

struct QuickStartPreset: Codable, Identifiable, Equatable {
    var id: UUID
    var duration: TimeInterval
    var label: String
    var alert: PresetAlertOptions
    var identity: TimerIdentity

    init(
        id: UUID = UUID(),
        duration: TimeInterval,
        label: String = "",
        alert: PresetAlertOptions = PresetAlertOptions(),
        identity: TimerIdentity = .default
    ) {
        self.id = id
        self.duration = min(max(duration.rounded(), 60), 24 * 60 * 60)
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.alert = alert
        self.identity = identity
    }

    func timerTemplate() -> TimerTemplate {
        TimerTemplate(
            duration: duration,
            options: TimerOptions(
                label: label.isEmpty ? "Timer" : label,
                soundName: alert.soundName,
                volume: alert.volume,
                loop: alert.loop,
                notify: alert.notify,
                snoozeMinutes: alert.snoozeMinutes,
                identity: identity
            ),
            origin: .preset
        )
    }
}
