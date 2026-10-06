import XCTest
@testable import DragTimer

final class CorruptStoreRecoveryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DragTimerRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func testReadableTimersSurviveAnUnreadableNeighbour() throws {
        let url = directory.appendingPathComponent("timers.json")
        let kept = TimerRecord(fireDate: Date().addingTimeInterval(600), options: TimerOptions(label: "Kept"))
        var records = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode([kept, kept])) as? [[String: Any]]
        )
        records[1]["fireDate"] = "not a date"
        try JSONSerialization.data(withJSONObject: records).write(to: url)

        let restored = TimerPersistence(fileURL: url).loadSalvagingReadableTimers()

        XCTAssertEqual(restored, [kept])
        XCTAssertEqual(try backups(of: "timers").count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testUnparseableTimersFileIsMovedAsideNotOverwritten() throws {
        let url = directory.appendingPathComponent("timers.json")
        try Data("not json".utf8).write(to: url)

        XCTAssertEqual(TimerPersistence(fileURL: url).loadSalvagingReadableTimers(), [])

        let backup = try XCTUnwrap(try backups(of: "timers").first)
        XCTAssertEqual(
            try String(contentsOf: directory.appendingPathComponent(backup), encoding: .utf8),
            "not json"
        )
    }

    func testHealthyAndMissingTimersFilesLeaveNoBackup() throws {
        let url = directory.appendingPathComponent("timers.json")
        let persistence = TimerPersistence(fileURL: url)
        XCTAssertEqual(persistence.loadSalvagingReadableTimers(), [])

        let record = TimerRecord(fireDate: Date().addingTimeInterval(600), options: TimerOptions(label: "Fine"))
        try persistence.save([record])

        XCTAssertEqual(persistence.loadSalvagingReadableTimers(), [record])
        XCTAssertEqual(try backups(of: "timers"), [])
    }

    func testEngineLaunchKeepsTheCorruptTimersFile() throws {
        let url = directory.appendingPathComponent("timers.json")
        try Data("[{\"broken\": true}]".utf8).write(to: url)

        let engine = TimerEngine(
            persistence: TimerPersistence(fileURL: url),
            notificationService: NotificationService(center: nil),
            audioPlayer: SilentAudio()
        )

        XCTAssertTrue(engine.timers.isEmpty)
        XCTAssertEqual(try backups(of: "timers").count, 1)
    }

    func testCorruptPendingExpiriesAreMovedAside() throws {
        let url = directory.appendingPathComponent("pending-expiries.json")
        try Data("not json".utf8).write(to: url)

        XCTAssertEqual(PendingExpiryStore(fileURL: url).load(), [])

        XCTAssertEqual(try backups(of: "pending-expiries").count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func backups(of name: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("\(name).corrupt-") && $0.hasSuffix(".json") }
    }

    private final class SilentAudio: AudioAlertPlaying {
        func play(timer: TimerRecord) {}
        func stop() {}
    }
}
