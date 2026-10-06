import Foundation

struct TimerPersistence {
    let fileURL: URL

    static var defaultStore: TimerPersistence {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = baseURL.appendingPathComponent("DragTimer", isDirectory: true)
        return TimerPersistence(fileURL: directory.appendingPathComponent("timers.json"))
    }

    func load() throws -> [TimerRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([TimerRecord].self, from: data)
    }

    /// Launch-time load. Records that still decode are kept even when their
    /// neighbours do not, and a file that lost anything is moved aside first
    /// because the engine saves over it straight after loading.
    func loadSalvagingReadableTimers() -> [TimerRecord] {
        if let timers = try? load() { return timers }
        let salvaged = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([Salvageable].self, from: $0) }?
            .compactMap(\.record) ?? []
        preserveCorruptFile(at: fileURL)
        return salvaged
    }

    private struct Salvageable: Decodable {
        let record: TimerRecord?

        init(from decoder: Decoder) throws {
            record = try? TimerRecord(from: decoder)
        }
    }

    func save(_ timers: [TimerRecord]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(timers)
        try data.write(to: fileURL, options: .atomic)
    }
}
