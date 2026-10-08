import Foundation

struct PresetAlertOptions: Codable, Equatable {
    var soundName: String
    var volume: Double
    var loop: Bool
    var notify: Bool
    var snoozeMinutes: Int
    var speaksName: Bool

    init(
        soundName: String = AlertSound.glass.rawValue,
        volume: Double = 0.8,
        loop: Bool = false,
        notify: Bool = true,
        snoozeMinutes: Int = 5,
        speaksName: Bool = false
    ) {
        self.soundName = AlertSound.normalizedName(soundName)
        self.volume = min(max(volume, 0), 1)
        self.loop = loop
        self.notify = notify
        self.snoozeMinutes = min(max(snoozeMinutes, 1), 60)
        self.speaksName = speaksName
    }

    private enum CodingKeys: String, CodingKey {
        case soundName, volume, loop, notify, snoozeMinutes, speaksName
    }

    /// Written out so that presets saved before `speaksName` existed still
    /// decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        soundName = try container.decode(String.self, forKey: .soundName)
        volume = try container.decode(Double.self, forKey: .volume)
        loop = try container.decode(Bool.self, forKey: .loop)
        notify = try container.decode(Bool.self, forKey: .notify)
        snoozeMinutes = try container.decode(Int.self, forKey: .snoozeMinutes)
        speaksName = try container.decodeIfPresent(Bool.self, forKey: .speaksName) ?? false
    }
}

extension PresetAlertOptions {
    init(_ options: TimerOptions) {
        self.init(
            soundName: options.soundName,
            volume: options.volume,
            loop: options.loop,
            notify: options.notify,
            snoozeMinutes: options.snoozeMinutes,
            speaksName: options.speaksName
        )
    }
}

extension TimerOptions {
    init(label: String, alert: PresetAlertOptions, identity: TimerIdentity = .default) {
        self.init(
            label: label,
            soundName: alert.soundName,
            volume: alert.volume,
            loop: alert.loop,
            notify: alert.notify,
            snoozeMinutes: alert.snoozeMinutes,
            identity: identity,
            speaksName: alert.speaksName
        )
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
        self.duration = min(max(duration.rounded(), 1), 24 * 60 * 60)
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.alert = alert
        self.identity = identity
    }

    func timerTemplate() -> TimerTemplate {
        TimerTemplate(
            duration: duration,
            options: TimerOptions(label: label.isEmpty ? "Timer" : label, alert: alert, identity: identity),
            origin: .preset
        )
    }
}
