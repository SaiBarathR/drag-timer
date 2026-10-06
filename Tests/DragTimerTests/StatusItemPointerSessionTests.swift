import XCTest
@testable import DragTimer

final class StatusItemPointerSessionTests: XCTestCase {
    private let origin = CGPoint(x: 500, y: 900)
    private let away = CGPoint(x: 500, y: 750)

    func testHeldPressWithJitterIsAClickOnlyOnRelease() {
        var session = StatusItemPointerSession(origin: origin)

        XCTAssertEqual(session.sample(pointer: origin, isPressed: true), [])
        XCTAssertEqual(session.sample(pointer: CGPoint(x: 502, y: 899), isPressed: true), [])
        XCTAssertEqual(session.sample(pointer: origin, isPressed: false), [.click])
        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(session.sample(pointer: origin, isPressed: false), [])
    }

    func testMovementPastActivationDistanceBecomesADragThatCannotTurnBackIntoAClick() {
        var session = StatusItemPointerSession(origin: origin)

        XCTAssertEqual(session.sample(pointer: away, isPressed: true), [.begin(origin, away)])
        XCTAssertEqual(session.sample(pointer: origin, isPressed: true), [.drag(origin)])
        XCTAssertEqual(session.sample(pointer: away, isPressed: false), [.end(away)])
    }

    func testActivationDistanceIsInclusive() {
        let distance = StatusItemPointerSession.activationDistance
        var below = StatusItemPointerSession(origin: origin)
        XCTAssertEqual(
            below.sample(pointer: CGPoint(x: origin.x, y: origin.y - distance + 0.5), isPressed: true),
            []
        )

        let edge = CGPoint(x: origin.x, y: origin.y - distance)
        var exactly = StatusItemPointerSession(origin: origin)
        XCTAssertEqual(exactly.sample(pointer: edge, isPressed: true), [.begin(origin, edge)])
    }

    func testMovementFirstSeenAtReleaseStillBeginsAndEndsADrag() {
        var session = StatusItemPointerSession(origin: origin)

        XCTAssertEqual(session.sample(pointer: away, isPressed: false), [.begin(origin, away), .end(away)])
    }
}
