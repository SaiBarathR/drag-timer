import Foundation

struct RoutineTimerDefinition: Codable, Identifiable, Equatable {
    var id: UUID
    var duration: TimeInterval
    var options: TimerOptions

    init(
        id: UUID = UUID(),
        duration: TimeInterval,
        options: TimerOptions
    ) {
        self.id = id
        self.duration = min(max(duration.rounded(), 60), 24 * 60 * 60)
        self.options = TimerOptions(
            label: options.label.trimmingCharacters(in: .whitespacesAndNewlines),
            soundName: options.soundName,
            volume: options.volume,
            loop: options.loop,
            notify: options.notify,
            snoozeMinutes: options.snoozeMinutes,
            identity: options.identity
        )
    }

    init(preset: QuickStartPreset) {
        self.init(
            duration: preset.duration,
            options: preset.timerTemplate().options
        )
    }

    func timerTemplate() -> TimerTemplate {
        TimerTemplate(duration: duration, options: options, origin: .routine)
    }
}

struct TimerRoutine: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var timers: [RoutineTimerDefinition]

    init(
        id: UUID = UUID(),
        name: String,
        timers: [RoutineTimerDefinition]
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.timers = timers.map {
            RoutineTimerDefinition(id: $0.id, duration: $0.duration, options: $0.options)
        }
    }

    var isValid: Bool {
        !name.isEmpty
            && !timers.isEmpty
            && timers.allSatisfy {
                !$0.options.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    var timerTemplates: [TimerTemplate] {
        timers.map { $0.timerTemplate() }
    }
}
