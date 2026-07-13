import AppKit
import Combine
import Foundation
import UserNotifications

enum NotificationTimerAction: String {
    case snooze
    case markDone
    case restart
}

enum NotificationPermissionState: Equatable {
    case unavailable
    case checking
    case notDetermined
    case denied
    case authorized
    case provisional
}

final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var permissionState: NotificationPermissionState = .checking

    private let center: UNUserNotificationCenter?
    private var actionHandler: ((UUID, NotificationTimerAction) -> Void)?
    private var queuedResponses: [(UUID, NotificationTimerAction)] = []

    private static let categoryIdentifier = "DRAG_TIMER_EXPIRED"
    private static let timerIDKey = "timerID"
    static let systemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
    )!

    init(center: UNUserNotificationCenter? = nil) {
        if let center {
            self.center = center
        } else if Bundle.main.bundleURL.pathExtension == "app" {
            // UNUserNotificationCenter requires an application bundle. Keep
            // the engine usable under `swift run`; the packaged app enables
            // this OS-delivered second alert channel automatically.
            self.center = .current()
        } else {
            self.center = nil
        }
        super.init()
        self.center?.delegate = self
        registerActions()
        refreshAuthorizationStatus()
    }

    func setActionHandler(_ handler: @escaping (UUID, NotificationTimerAction) -> Void) {
        actionHandler = handler
        let responses = queuedResponses
        queuedResponses.removeAll()
        for (timerID, action) in responses {
            handler(timerID, action)
        }
    }

    func requestAuthorization() {
        guard let center else {
            permissionState = .unavailable
            return
        }
        center.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] _, _ in
            self?.refreshAuthorizationStatus()
        }
    }

    func refreshAuthorizationStatus() {
        guard let center else {
            permissionState = .unavailable
            return
        }
        center.getNotificationSettings { [weak self] settings in
            let state = Self.permissionState(for: settings.authorizationStatus)
            DispatchQueue.main.async {
                self?.permissionState = state
            }
        }
    }

    func openSystemSettings() {
        NSWorkspace.shared.open(Self.systemSettingsURL)
    }

    static func permissionState(for status: UNAuthorizationStatus) -> NotificationPermissionState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        @unknown default:
            return .unavailable
        }
    }

    func schedule(_ timer: TimerRecord) {
        guard let center else { return }
        remove(timerID: timer.id)
        guard timer.notify else { return }

        let interval = max(1, timer.fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: timer.id),
            content: content(for: timer),
            trigger: trigger
        )
        center.add(request) { _ in }
    }

    func deliverImmediately(_ timer: TimerRecord) {
        guard let center, timer.notify else { return }
        let request = UNNotificationRequest(
            identifier: identifier(for: timer.id),
            content: content(for: timer),
            trigger: nil
        )
        center.add(request) { _ in }
    }

    func remove(timerID: UUID) {
        guard let center else { return }
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: timerID)])
    }

    private func identifier(for timerID: UUID) -> String {
        "com.dragtimer.timer.\(timerID.uuidString)"
    }

    private func content(for timer: TimerRecord) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Timer finished"
        content.body = timer.label
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo[Self.timerIDKey] = timer.id.uuidString
        return content
    }

    private func registerActions() {
        guard let center else { return }
        let actions = [
            UNNotificationAction(identifier: NotificationTimerAction.snooze.rawValue, title: "Snooze"),
            UNNotificationAction(identifier: NotificationTimerAction.markDone.rawValue, title: "Mark done"),
            UNNotificationAction(identifier: NotificationTimerAction.restart.rawValue, title: "Restart")
        ]
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryIdentifier,
                actions: actions,
                intentIdentifiers: []
            )
        ])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // The app is running whenever this delegate is called, so the in-app
        // AudioAlertPlayer already provides the sound. Presenting the
        // notification's own sound on top of it would double the alert.
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let rawTimerID = response.notification.request.content.userInfo[Self.timerIDKey] as? String,
              let timerID = UUID(uuidString: rawTimerID),
              let action = NotificationTimerAction(rawValue: response.actionIdentifier) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let actionHandler {
                actionHandler(timerID, action)
            } else {
                queuedResponses.append((timerID, action))
            }
        }
    }
}
