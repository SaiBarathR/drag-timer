import XCTest
@testable import DragTimer

final class DeadlineHeapTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 100)

    func testPopsInDeadlineOrder() {
        let records = [30, 10, 20].map(record(after:))
        var heap = DeadlineHeap()
        records.forEach { heap.insert($0) }

        XCTAssertEqual(heap.peek?.id, records[1].id)
        XCTAssertEqual(drain(&heap).map(\.id), [records[1].id, records[2].id, records[0].id])
        XCTAssertNil(heap.pop())
    }

    func testEqualDeadlinesPopInIdentifierOrder() {
        let records = (0..<6).map { _ in record(after: 10) }
        var heap = DeadlineHeap()
        records.forEach { heap.insert($0) }

        XCTAssertEqual(drain(&heap).map(\.id.uuidString), records.map(\.id.uuidString).sorted())
    }

    func testReplaceReportsWhetherTheTimerWasPresent() {
        var heap = DeadlineHeap()
        var known = record(after: 10)
        heap.insert(known)
        known.fireDate = start.addingTimeInterval(99)

        XCTAssertTrue(heap.replace(known))
        XCTAssertFalse(heap.replace(record(after: 5)))
        XCTAssertNil(heap.remove(id: UUID()))
        XCTAssertEqual(heap.peek?.fireDate, known.fireDate)
    }

    /// Random inserts, removals and deadline changes must leave the heap
    /// draining in the same order as a plain sorted array.
    func testMatchesASortedArrayUnderRandomMutation() {
        var generator = SeededGenerator(seed: 0xD4A6)
        for _ in 0..<50 {
            var heap = DeadlineHeap()
            var model: [TimerRecord] = []
            for _ in 0..<80 {
                switch Int.random(in: 0..<4, using: &generator) {
                case 0 where !model.isEmpty:
                    let victim = model.remove(at: Int.random(in: 0..<model.count, using: &generator))
                    XCTAssertEqual(heap.remove(id: victim.id)?.id, victim.id)
                case 1 where !model.isEmpty:
                    let index = Int.random(in: 0..<model.count, using: &generator)
                    model[index].fireDate = start.addingTimeInterval(
                        Double(Int.random(in: 0..<40, using: &generator))
                    )
                    XCTAssertTrue(heap.replace(model[index]))
                default:
                    let added = record(after: Double(Int.random(in: 0..<40, using: &generator)))
                    model.append(added)
                    heap.insert(added)
                }
                XCTAssertEqual(heap.count, model.count)
            }
            let expected = model.sorted {
                $0.fireDate != $1.fireDate ? $0.fireDate < $1.fireDate : $0.id.uuidString < $1.id.uuidString
            }
            XCTAssertEqual(drain(&heap).map(\.id), expected.map(\.id))
        }
    }

    private func record(after seconds: TimeInterval) -> TimerRecord {
        TimerRecord(
            createdAt: start,
            fireDate: start.addingTimeInterval(seconds),
            options: TimerOptions(label: "Heap")
        )
    }

    private func drain(_ heap: inout DeadlineHeap) -> [TimerRecord] {
        var popped: [TimerRecord] = []
        while let next = heap.pop() { popped.append(next) }
        return popped
    }

    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
