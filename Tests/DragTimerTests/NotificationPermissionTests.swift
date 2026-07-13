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

    func testNotificationSettingsDeepLinkTargetsNotificationsPane() {
        XCTAssertEqual(NotificationService.systemSettingsURL.scheme, "x-apple.systempreferences")
        XCTAssertTrue(NotificationService.systemSettingsURL.absoluteString.contains("Notifications-Settings"))
    }
}
