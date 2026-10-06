import Foundation

struct TimerHistoryStore {
    let fileURL: URL
    var maximumEntries = 500
    var retentionInterval: TimeInterval = 90 * 24 * 60 * 60

    func load(now: Date = Date()) -> [TimerHistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let entries = try JSONDecoder().decode([TimerHistoryEntry].self, from: data)
            return retained(entries, now: now)
        } catch {
            preserveCorruptFile(at: fileURL)
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

}

struct PendingExpiryStore {
    let fileURL: URL

    func load() -> [PendingExpiry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let values = try? JSONDecoder().decode([PendingExpiry].self, from: data) else {
            preserveCorruptFile(at: fileURL)
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

/// Moves an unreadable store aside so the next save cannot overwrite the only
/// copy of the user's data.
func preserveCorruptFile(at fileURL: URL) {
    let backupURL = fileURL.deletingPathExtension()
        .appendingPathExtension(
            "corrupt-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString).json"
        )
    try? FileManager.default.moveItem(at: fileURL, to: backupURL)
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
