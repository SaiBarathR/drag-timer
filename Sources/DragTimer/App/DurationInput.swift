import Foundation

/// Reads a typed timer length: "7", "25m", "1h", "1h30", "1h 30m", "1.5 hr",
/// "90 min" or "1:30". A bare number is minutes, or minutes after an hours
/// part. The result is whole minutes between one minute and one day.
enum DurationInput {
    static let range: ClosedRange<TimeInterval> = 60...(24 * 60 * 60)

    static func parse(_ text: String) -> TimeInterval? {
        let input = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, input.count <= 24 else { return nil }

        let clock = input.split(separator: ":", omittingEmptySubsequences: false)
        if clock.count == 2 {
            guard let hours = wholeNumber(clock[0]), let minutes = wholeNumber(clock[1]),
                  minutes < 60 else { return nil }
            return bounded(minutes: hours * 60 + minutes)
        }

        var minutes = 0.0
        var sawHours = false
        var sawMinutes = false
        var rest = Substring(input)
        while !rest.isEmpty {
            let digits = rest.prefix { $0.isNumber || $0 == "." }
            guard let value = Double(digits), value.isFinite, value < 100_000 else { return nil }
            rest = rest.dropFirst(digits.count).drop { $0 == " " }
            let unit = rest.prefix { $0.isLetter }
            rest = rest.dropFirst(unit.count).drop { $0 == " " }

            switch unit {
            case "h", "hr", "hrs", "hour", "hours":
                guard !sawHours, !sawMinutes else { return nil }
                sawHours = true
                minutes += value * 60
            case "", "m", "min", "mins", "minute", "minutes":
                guard !sawMinutes else { return nil }
                sawMinutes = true
                minutes += value
            default:
                return nil
            }
        }
        return bounded(minutes: minutes)
    }

    private static func wholeNumber(_ text: Substring) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 4, trimmed.allSatisfy(\.isNumber) else { return nil }
        return Double(trimmed)
    }

    private static func bounded(minutes: Double) -> TimeInterval? {
        let duration = (minutes.rounded()) * 60
        return range.contains(duration) ? duration : nil
    }
}
