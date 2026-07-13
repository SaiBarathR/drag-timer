import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private lazy var timerEngine = TimerEngine(
        persistence: .defaultStore,
        notificationService: NotificationService(),
        audioPlayer: AudioAlertPlayer(),
        shouldFirePastDueOnWake: { [weak settings] in
            settings?.firePastDueOnWake ?? true
        }
    )

    private var statusItemController: StatusItemController?
    private var popoverController: TimerPopoverController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let popoverController = TimerPopoverController(
            timerEngine: timerEngine,
            settings: settings,
            onOpenSettings: { [weak self] in
                self?.showSettings()
            },
            onPopoverVisibilityChanged: { [weak self] isVisible in
                self?.statusItemController?.setPopoverVisible(isVisible)
            }
        )
        self.popoverController = popoverController

        statusItemController = StatusItemController(
            timerEngine: timerEngine,
            settings: settings,
            onPopoverRequested: { [weak popoverController] button in
                popoverController?.toggle(relativeTo: button)
            }
        )

        timerEngine.requestNotificationAuthorization()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timerEngine.flushPersistence()
    }

    private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: settings)
        }
        settingsWindowController?.showWindow(nil)
    }

}
