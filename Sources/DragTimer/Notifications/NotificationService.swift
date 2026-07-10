import Foundation
import UserNotifications

final class NotificationService {
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
    }

    func requestAuthorization() {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .badge]) { _, _ in }
    }

    func schedule(_ timer: TimerRecord) {
        guard let center else { return }
        remove(timerID: timer.id)
        guard timer.notify else { return }

        let content = UNMutableNotificationContent()
        content.title = "Timer finished"
        content.body = timer.label

        let interval = max(1, timer.fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: timer.id),
            content: content,
            trigger: trigger
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
}
