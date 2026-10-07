import XCTest
import UserNotifications
@testable import DragTimer

final class NotificationPermissionTests: XCTestCase {
    func testAuthorizationStatusMapping() {
        XCTAssertEqual(NotificationService.permissionState(for: .notDetermined), .notDetermined)
        XCTAssertEqual(NotificationService.permissionState(for: .denied), .denied)
        XCTAssertEqual(NotificationService.permissionState(for: .authorized), .authorized)
        XCTAssertEqual(NotificationService.permissionState(for: .provisional), .provisional)
    }

    func testTimersAreRescheduledOnlyWhenPermissionIsNewlyGranted() {
        XCTAssertTrue(TimerEngine.permissionWasGranted(from: .notDetermined, to: .authorized))
        XCTAssertTrue(TimerEngine.permissionWasGranted(from: .denied, to: .authorized))
        XCTAssertTrue(TimerEngine.permissionWasGranted(from: .notDetermined, to: .provisional))
        // Every launch goes from checking to the stored answer; nothing to redo.
        XCTAssertFalse(TimerEngine.permissionWasGranted(from: .checking, to: .authorized))
        XCTAssertFalse(TimerEngine.permissionWasGranted(from: .authorized, to: .authorized))
        XCTAssertFalse(TimerEngine.permissionWasGranted(from: .authorized, to: .denied))
        XCTAssertFalse(TimerEngine.permissionWasGranted(from: .notDetermined, to: .denied))
    }

    func testNotificationSettingsDeepLinkTargetsNotificationsPane() {
        XCTAssertEqual(NotificationService.systemSettingsURL.scheme, "x-apple.systempreferences")
        XCTAssertTrue(NotificationService.systemSettingsURL.absoluteString.contains("Notifications-Settings"))
    }
}
