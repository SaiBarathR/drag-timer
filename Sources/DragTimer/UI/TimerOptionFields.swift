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
        .onChange(of: options.soundName) { _, soundName in
            SoundPreview.play(soundName: soundName, volume: options.volume)
        }
        if options.soundName == AlertSound.systemBeep.rawValue {
            Text("System beep uses your Mac's alert volume.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        LabeledContent("Volume") {
            Slider(value: $options.volume, in: 0...1)
                // The spoken name follows this volume even when the beep
                // does not.
                .disabled(options.soundName == AlertSound.systemBeep.rawValue && !options.speaksName)
        }
        Toggle("Loop sound", isOn: $options.loop)
        Toggle("Say the timer's name", isOn: $options.speaksName)
        Toggle("Show notification", isOn: $options.notify)
        Stepper("Snooze for \(options.snoozeMinutes) min", value: $options.snoozeMinutes, in: 1...60)
    }
}

/// A length typed as text and read with `DurationInput`, instead of stepping
/// one minute at a time toward a two-hour timer. A text binding updates on
/// every keystroke, so Save always sees what is in the field; a formatted
/// number field commits only on Return or when focus leaves it.
struct DurationField: View {
    @Binding var text: String

    var body: some View {
        LabeledContent("Duration") {
            HStack(spacing: 8) {
                TextField("25m, 1h 30m", text: $text)
                    .labelsHidden()
                    .frame(width: 110)
                    .accessibilityLabel("Duration")
                if let duration = DurationInput.parse(text) {
                    Text(DurationText.planned(duration))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Use 25m or 1h 30m")
                        .foregroundStyle(.red)
                }
            }
            .font(.callout)
        }
    }

    /// How an existing length is shown for editing, in a form the field
    /// reads back to the same value.
    static func text(for duration: TimeInterval) -> String {
        DurationText.dragSelection(duration)
    }
}
