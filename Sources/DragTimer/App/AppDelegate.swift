import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let notificationService = NotificationService()
    private lazy var timerEngine = TimerEngine(
        persistence: .defaultStore,
        notificationService: notificationService,
        audioPlayer: AudioAlertPlayer(),
        shouldFirePastDueOnWake: { [weak settings] in
            settings?.firePastDueOnWake ?? true
        }
    )
    private lazy var updateChecker = UpdateChecker(settings: settings)

    private var statusItemController: StatusItemController?
    private var popoverController: TimerPopoverController?
    private var settingsWindowController: SettingsWindowController?
    private var historyWindowController: HistoryWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let popoverController = TimerPopoverController(
            timerEngine: timerEngine,
            settings: settings,
            updateChecker: updateChecker,
            onOpenSettings: { [weak self] in
                self?.showSettings()
            },
            onOpenHistory: { [weak self] in
                self?.showHistory()
            },
            onPopoverVisibilityChanged: { [weak self] isVisible in
                self?.statusItemController?.setPopoverVisible(isVisible)
            }
        )
        self.popoverController = popoverController

        statusItemController = StatusItemController(
            timerEngine: timerEngine,
            settings: settings,
            onPopoverRequested: { [weak popoverController] view, positioningRect in
                popoverController?.toggle(relativeTo: view, positioningRect: positioningRect)
            },
            onPopoverAnchorChanged: { [weak popoverController] view, positioningRect in
                popoverController?.updatePositioningRect(positioningRect, relativeTo: view)
            }
        )

        timerEngine.requestNotificationAuthorization()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await self?.updateChecker.checkIfNeeded()
        }

    }

    func applicationWillTerminate(_ notification: Notification) {
        timerEngine.flushPersistence()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        notificationService.refreshAuthorizationStatus()
    }

    private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: settings,
                updateChecker: updateChecker,
                notificationService: notificationService
            )
        }
        settingsWindowController?.showWindow(nil)
    }

    private func showHistory() {
        if historyWindowController == nil {
            historyWindowController = HistoryWindowController(timerEngine: timerEngine)
        }
        historyWindowController?.showWindow(nil)
    }

}
