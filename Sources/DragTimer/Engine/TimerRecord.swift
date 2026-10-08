import Foundation

enum TimerColorToken: String, Codable, CaseIterable, Identifiable {
    case blue
    case amber
    case mint
    case violet
    case red
    case graphite

    var id: String { rawValue }
}

struct TimerIdentity: Codable, Equatable {
    var color: TimerColorToken
    var symbolName: String

    static let `default` = TimerIdentity(color: .blue, symbolName: "clock")

    init(color: TimerColorToken = .blue, symbolName: String = "clock") {
        self.color = color
        self.symbolName = Self.allowedSymbols.contains(symbolName) ? symbolName : "clock"
    }

    static let allowedSymbols = [
        "clock", "cup.and.saucer.fill", "book.fill", "figure.run", "washer.fill",
        "flame.fill", "pills.fill", "briefcase.fill", "leaf.fill", "music.note"
    ]

    static func displayName(forSymbol name: String) -> String {
        switch name {
        case "cup.and.saucer.fill": return "Coffee"
        case "book.fill": return "Reading"
        case "figure.run": return "Exercise"
        case "washer.fill": return "Laundry"
        case "flame.fill": return "Cooking"
        case "pills.fill": return "Medication"
        case "briefcase.fill": return "Work"
        case "leaf.fill": return "Break"
        case "music.note": return "Music"
        default: return "Clock"
        }
    }

    private enum CodingKeys: String, CodingKey { case color, symbolName }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawColor = (try? container.decode(String.self, forKey: .color)) ?? TimerColorToken.blue.rawValue
        let rawSymbol = (try? container.decode(String.self, forKey: .symbolName)) ?? "clock"
        self.init(
            color: TimerColorToken(rawValue: rawColor) ?? .blue,
            symbolName: rawSymbol
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color.rawValue, forKey: .color)
        try container.encode(symbolName, forKey: .symbolName)
    }
}

enum TimerOrigin: String, Codable, Equatable {
    case drag
    case preset
    case routine
    case history
    case snooze
    case restart
}

enum AlertSound: String, Codable, CaseIterable, Identifiable {
    // Every raw value but the last is the name of a file in
    // /System/Library/Sounds, which is where the sound is played from.
    case basso = "Basso"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case glass = "Glass"
    case hero = "Hero"
    case morse = "Morse"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case tink = "Tink"
    case systemBeep = "System"

    var id: String { rawValue }

    var displayName: String {
        self == .systemBeep ? "System beep" : rawValue
    }

    /// Nil for the system beep, which macOS plays itself.
    var fileURL: URL? {
        guard self != .systemBeep else { return nil }
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(rawValue).aiff")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Old builds stored the default as "Pulse" even though the packaged app
    /// played Glass as its fallback. Keep those saved timers valid, and fall
    /// back to Glass for a name this build does not know.
    static func normalizedName(_ rawValue: String) -> String {
        (AlertSound(rawValue: rawValue) ?? .glass).rawValue
    }
}

struct TimerOptions: Codable, Equatable {
    var label: String
    var soundName: String
    var volume: Double
    var loop: Bool
    var notify: Bool
    var snoozeMinutes: Int
    var identity: TimerIdentity
    /// Says "<label> finished" aloud after the sound.
    var speaksName: Bool

    init(
        label: String,
        soundName: String = AlertSound.glass.rawValue,
        volume: Double = 0.8,
        loop: Bool = false,
        notify: Bool = true,
        snoozeMinutes: Int = 5,
        identity: TimerIdentity = .default,
        speaksName: Bool = false
    ) {
        self.label = label
        self.soundName = AlertSound.normalizedName(soundName)
        self.volume = min(max(volume, 0), 1)
        self.loop = loop
        self.notify = notify
        self.snoozeMinutes = max(1, snoozeMinutes)
        self.identity = identity
        self.speaksName = speaksName
    }

    private enum CodingKeys: String, CodingKey {
        case label, soundName, volume, loop, notify, snoozeMinutes, identity, speaksName
    }

    /// Written out so that routines and history saved before `speaksName`
    /// existed still decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        soundName = try container.decode(String.self, forKey: .soundName)
        volume = try container.decode(Double.self, forKey: .volume)
        loop = try container.decode(Bool.self, forKey: .loop)
        notify = try container.decode(Bool.self, forKey: .notify)
        snoozeMinutes = try container.decode(Int.self, forKey: .snoozeMinutes)
        identity = try container.decode(TimerIdentity.self, forKey: .identity)
        speaksName = try container.decodeIfPresent(Bool.self, forKey: .speaksName) ?? false
    }
}

struct TimerRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var fireDate: Date
    /// Optional so timers saved by older releases continue to decode.
    var originalDuration: TimeInterval?
    var pausedRemaining: TimeInterval?
    var label: String
    var soundName: String
    var volume: Double
    var loop: Bool
    var notify: Bool
    var snoozeMinutes: Int
    /// Optional so timers saved by v1.2.0 and earlier continue to decode.
    var identity: TimerIdentity?
    /// Optional for backward-compatible decoding; `.drag` is the runtime default.
    var origin: TimerOrigin?
    var parentEventID: UUID?
    /// Optional so timers saved by v1.5.0 and earlier continue to decode.
    var speaksName: Bool?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        fireDate: Date,
        options: TimerOptions,
        origin: TimerOrigin = .drag,
        parentEventID: UUID? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.fireDate = fireDate
        self.originalDuration = max(1, fireDate.timeIntervalSince(createdAt))
        self.pausedRemaining = nil
        let trimmedLabel = options.label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = trimmedLabel.isEmpty ? "Timer" : trimmedLabel
        self.soundName = AlertSound.normalizedName(options.soundName)
        self.volume = min(max(options.volume, 0), 1)
        self.loop = options.loop
        self.notify = options.notify
        self.snoozeMinutes = max(1, options.snoozeMinutes)
        self.identity = options.identity
        self.origin = origin
        self.parentEventID = parentEventID
        self.speaksName = options.speaksName
    }

    /// Replaces everything an editor can change, leaving timing untouched.
    mutating func apply(_ options: TimerOptions) {
        let trimmedLabel = options.label.trimmingCharacters(in: .whitespacesAndNewlines)
        label = trimmedLabel.isEmpty ? "Timer" : trimmedLabel
        soundName = AlertSound.normalizedName(options.soundName)
        volume = min(max(options.volume, 0), 1)
        loop = options.loop
        notify = options.notify
        snoozeMinutes = max(1, options.snoozeMinutes)
        identity = options.identity
        speaksName = options.speaksName
    }

    var options: TimerOptions {
        TimerOptions(
            label: label,
            soundName: soundName,
            volume: volume,
            loop: loop,
            notify: notify,
            snoozeMinutes: snoozeMinutes,
            identity: resolvedIdentity,
            speaksName: speaksName ?? false
        )
    }

    var resolvedIdentity: TimerIdentity { identity ?? .default }
    var resolvedOrigin: TimerOrigin { origin ?? .drag }

    func remaining(at date: Date = Date()) -> TimeInterval {
        max(0, pausedRemaining ?? fireDate.timeIntervalSince(date))
    }

    var isPaused: Bool {
        pausedRemaining != nil
    }

    var resetDuration: TimeInterval {
        max(1, originalDuration ?? fireDate.timeIntervalSince(createdAt))
    }

    func progress(at date: Date = Date()) -> Double {
        let total = resetDuration
        return min(1, max(0, 1 - (remaining(at: date) / total)))
    }
}

struct TimerTemplate: Codable, Equatable {
    var duration: TimeInterval
    var options: TimerOptions
    var origin: TimerOrigin
    var parentEventID: UUID?

    init(
        duration: TimeInterval,
        options: TimerOptions,
        origin: TimerOrigin,
        parentEventID: UUID? = nil
    ) {
        self.duration = min(max(duration.rounded(), 1), 24 * 60 * 60)
        self.options = options
        self.origin = origin
        self.parentEventID = parentEventID
    }
}
