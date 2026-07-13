import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter?

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
    }

    func requestAuthorization() {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
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
        return content
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
}
