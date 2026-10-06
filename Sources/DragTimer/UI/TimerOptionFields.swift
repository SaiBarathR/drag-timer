import SwiftUI

/// The sound, notification, snooze and identity rows shared by every timer
/// editor: a running timer in the popover, a Quick start preset and a routine
/// timer in Preferences.
struct TimerOptionFields: View {
    @Binding var options: TimerOptions

    var body: some View {
        Picker("Color", selection: $options.identity.color) {
            ForEach(TimerColorToken.allCases) { Text($0.displayName).tag($0) }
        }
        Picker("Symbol", selection: $options.identity.symbolName) {
            ForEach(TimerIdentity.allowedSymbols, id: \.self) { name in
                Label(TimerIdentity.displayName(forSymbol: name), systemImage: name).tag(name)
            }
        }
        Picker("Sound", selection: $options.soundName) {
            ForEach(AlertSound.allCases) { Text($0.displayName).tag($0.rawValue) }
        }
        if options.soundName == AlertSound.systemBeep.rawValue {
            Text("System beep uses your Mac's alert volume.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        LabeledContent("Volume") {
            Slider(value: $options.volume, in: 0...1)
                .disabled(options.soundName == AlertSound.systemBeep.rawValue)
        }
        Toggle("Loop sound", isOn: $options.loop)
        Toggle("Show notification", isOn: $options.notify)
        Stepper("Snooze for \(options.snoozeMinutes) min", value: $options.snoozeMinutes, in: 1...60)
    }
}

/// Hours and minutes typed directly, instead of stepping one minute at a time
/// toward a two-hour timer.
struct DurationFields: View {
    @Binding var minutes: Int

    static let range = 1...(24 * 60)

    var body: some View {
        LabeledContent("Duration") {
            HStack(spacing: 6) {
                field(value: hours, label: "Hours")
                Text("hr").foregroundStyle(.secondary)
                field(value: remainder, label: "Minutes")
                Text("min").foregroundStyle(.secondary)
            }
        }
    }

    private func field(value: Binding<Int>, label: String) -> some View {
        TextField(label, value: value, format: .number)
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 44)
            .accessibilityLabel(label)
    }

    private var hours: Binding<Int> {
        Binding(
            get: { minutes / 60 },
            set: { minutes = Self.clamped(hours: $0, minutes: minutes % 60) }
        )
    }

    private var remainder: Binding<Int> {
        Binding(
            get: { minutes % 60 },
            set: { minutes = Self.clamped(hours: minutes / 60, minutes: $0) }
        )
    }

    /// Typing 90 in the minutes field carries into the hours field.
    static func clamped(hours: Int, minutes: Int) -> Int {
        // Bound each part first: a pasted 18-digit number must not overflow.
        let boundedHours = min(max(hours, 0), range.upperBound / 60)
        let boundedMinutes = min(max(minutes, 0), range.upperBound)
        return min(max(boundedHours * 60 + boundedMinutes, range.lowerBound), range.upperBound)
    }
}
