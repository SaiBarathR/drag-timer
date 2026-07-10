import Foundation

/// A small binary min-heap keyed by absolute fire dates. The timer engine owns
/// exactly one scheduler and only ever arms it for `peek()`.
struct DeadlineHeap {
    private var storage: [TimerRecord] = []

    var count: Int { storage.count }
    var isEmpty: Bool { storage.isEmpty }
    var peek: TimerRecord? { storage.first }

    mutating func insert(_ timer: TimerRecord) {
        storage.append(timer)
        siftUp(from: storage.count - 1)
    }

    mutating func pop() -> TimerRecord? {
        guard !storage.isEmpty else { return nil }
        if storage.count == 1 {
            return storage.removeLast()
        }

        let first = storage[0]
        storage[0] = storage.removeLast()
        siftDown(from: 0)
        return first
    }

    @discardableResult
    mutating func remove(id: UUID) -> TimerRecord? {
        guard let index = storage.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = storage[index]

        if index == storage.count - 1 {
            storage.removeLast()
            return removed
        }

        storage[index] = storage.removeLast()
        repair(at: index)
        return removed
    }

    @discardableResult
    mutating func replace(_ timer: TimerRecord) -> Bool {
        guard let index = storage.firstIndex(where: { $0.id == timer.id }) else { return false }
        storage[index] = timer
        repair(at: index)
        return true
    }

    private mutating func repair(at index: Int) {
        let parent = (index - 1) / 2
        if index > 0 && comesBefore(storage[index], storage[parent]) {
            siftUp(from: index)
        } else {
            siftDown(from: index)
        }
    }

    private mutating func siftUp(from start: Int) {
        var child = start
        while child > 0 {
            let parent = (child - 1) / 2
            guard comesBefore(storage[child], storage[parent]) else { return }
            storage.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(from start: Int) {
        var parent = start
        while true {
            let left = (parent * 2) + 1
            let right = left + 1
            var candidate = parent

            if left < storage.count && comesBefore(storage[left], storage[candidate]) {
                candidate = left
            }
            if right < storage.count && comesBefore(storage[right], storage[candidate]) {
                candidate = right
            }
            guard candidate != parent else { return }
            storage.swapAt(parent, candidate)
            parent = candidate
        }
    }

    private func comesBefore(_ lhs: TimerRecord, _ rhs: TimerRecord) -> Bool {
        if lhs.fireDate != rhs.fireDate {
            return lhs.fireDate < rhs.fireDate
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
