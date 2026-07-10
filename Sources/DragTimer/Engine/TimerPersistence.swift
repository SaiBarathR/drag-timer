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
