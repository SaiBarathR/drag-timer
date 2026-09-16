import Foundation

/// A forwarded status-item activation can arrive as a synthetic click while
/// the real button is still down. Classify that press using physical samples.
struct StatusItemPointerSession {
    static let activationDistance: CGFloat = 8
    enum Action: Equatable {
        case begin(CGPoint, CGPoint)
        case drag(CGPoint)
        case end(CGPoint)
        case click
    }

    let origin: CGPoint
    private var isDragging = false
    private(set) var isFinished = false

    init(origin: CGPoint) { self.origin = origin }

    mutating func sample(pointer: CGPoint, isPressed: Bool) -> [Action] {
        guard !isFinished else { return [] }
        var actions: [Action] = []
        if !isDragging && hypot(pointer.x - origin.x, pointer.y - origin.y) >= Self.activationDistance {
            isDragging = true
            actions.append(.begin(origin, pointer))
        } else if isDragging && isPressed {
            actions.append(.drag(pointer))
        }
        if !isPressed {
            isFinished = true
            actions.append(isDragging ? .end(pointer) : .click)
        }
        return actions
    }
}
