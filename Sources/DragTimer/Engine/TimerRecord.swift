import Foundation

enum AlertSound: String, Codable, CaseIterable, Identifiable {
    case glass = "Glass"
    case systemBeep = "System"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .glass:
            return "Glass"
        case .systemBeep:
            return "System beep"
        }
    }

    /// Old builds stored the default as "Pulse" even though the packaged app
    /// played Glass as its fallback. Keep those saved timers valid while making
    /// the actual selected sound explicit going forward.
    static func normalizedName(_ rawValue: String) -> String {
        switch rawValue {
        case AlertSound.systemBeep.rawValue:
            return AlertSound.systemBeep.rawValue
        case AlertSound.glass.rawValue, "Pulse":
            return AlertSound.glass.rawValue
        default:
            return AlertSound.glass.rawValue
        }
    }
}

struct TimerOptions: Codable, Equatable {
    var label: String
    var soundName: String
    var volume: Double
    var loop: Bool
    var notify: Bool
    var snoozeMinutes: Int

    init(
        label: String,
        soundName: String = AlertSound.glass.rawValue,
        volume: Double = 0.8,
        loop: Bool = false,
        notify: Bool = true,
        snoozeMinutes: Int = 5
    ) {
        self.label = label
        self.soundName = AlertSound.normalizedName(soundName)
        self.volume = min(max(volume, 0), 1)
        self.loop = loop
        self.notify = notify
        self.snoozeMinutes = max(1, snoozeMinutes)
    }
}

struct TimerRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var fireDate: Date
    var label: String
    var soundName: String
    var volume: Double
    var loop: Bool
    var notify: Bool
    var snoozeMinutes: Int

    init(id: UUID = UUID(), createdAt: Date = Date(), fireDate: Date, options: TimerOptions) {
        self.id = id
        self.createdAt = createdAt
        self.fireDate = fireDate
        self.label = options.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Timer" : options.label
        self.soundName = AlertSound.normalizedName(options.soundName)
        self.volume = min(max(options.volume, 0), 1)
        self.loop = options.loop
        self.notify = options.notify
        self.snoozeMinutes = max(1, options.snoozeMinutes)
    }

    var options: TimerOptions {
        TimerOptions(
            label: label,
            soundName: soundName,
            volume: volume,
            loop: loop,
            notify: notify,
            snoozeMinutes: snoozeMinutes
        )
    }

    func remaining(at date: Date = Date()) -> TimeInterval {
        max(0, fireDate.timeIntervalSince(date))
    }
}
