import Foundation

struct TimerHistoryStore {
    let fileURL: URL
    var maximumEntries = 500
    var retentionInterval: TimeInterval = 90 * 24 * 60 * 60

    static var defaultStore: TimerHistoryStore {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = baseURL.appendingPathComponent("DragTimer", isDirectory: true)
        return TimerHistoryStore(fileURL: directory.appendingPathComponent("history.json"))
    }

    func load(now: Date = Date()) -> [TimerHistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let entries = try JSONDecoder().decode([TimerHistoryEntry].self, from: data)
            return retained(entries, now: now)
        } catch {
            preserveCorruptFile()
            return []
        }
    }

    func save(_ entries: [TimerHistoryEntry], now: Date = Date()) throws {
        try saveJSON(retained(entries, now: now), to: fileURL)
    }

    func retained(_ entries: [TimerHistoryEntry], now: Date) -> [TimerHistoryEntry] {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        return Array(entries
            .filter { $0.endedAt >= cutoff }
            .sorted { lhs, rhs in
                if lhs.endedAt != rhs.endedAt { return lhs.endedAt > rhs.endedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(maximumEntries))
    }

    private func preserveCorruptFile() {
        let backupURL = fileURL.deletingPathExtension()
            .appendingPathExtension(
                "corrupt-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString).json"
            )
        try? FileManager.default.moveItem(at: fileURL, to: backupURL)
    }
}

struct PendingExpiryStore {
    let fileURL: URL

    static var defaultStore: PendingExpiryStore {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = baseURL.appendingPathComponent("DragTimer", isDirectory: true)
        return PendingExpiryStore(fileURL: directory.appendingPathComponent("pending-expiries.json"))
    }

    func load() -> [PendingExpiry] {
        guard let data = try? Data(contentsOf: fileURL),
              let values = try? JSONDecoder().decode([PendingExpiry].self, from: data) else {
            return []
        }
        return values.sorted { lhs, rhs in
            if lhs.expiredAt != rhs.expiredAt { return lhs.expiredAt < rhs.expiredAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func save(_ expiries: [PendingExpiry]) throws {
        try saveJSON(expiries, to: fileURL)
    }
}

private func saveJSON<T: Encodable>(_ value: T, to fileURL: URL) throws {
    try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: fileURL, options: .atomic)
}
