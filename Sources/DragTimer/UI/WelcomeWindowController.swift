import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The window the guide is in.
///
/// Drag Timer has no main window to put a sheet over, so the guide has one of
/// its own, and the app goes on working behind it: a timer can be pulled out
/// of the menu bar with the page that describes the drag still on screen.
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private let pager = WelcomePager()
    private let onClose: () -> Void

    /// `onClose` is told when the guide is shut, by any of the ways there
    /// are to shut it.
    init(onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
        let size = NSSize(
            width: WelcomeGuide.size.width,
            height: WelcomeGuide.height(
                fitting: NSScreen.main?.visibleFrame.height ?? WelcomeGuide.size.height
            )
        )
        let window = WelcomeWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Read out, and listed in Mission Control; the guide's own heading
        // is what is seen.
        window.title = "Welcome to Drag Timer"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // It can only be shut: two buttons that are always grey say nothing.
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.onArrow = { [pager] direction in pager.step(direction) }
        super.init(window: window)

        let guide = NSHostingView(
            rootView: WelcomeGuide(pager: pager) { [weak self] in
                self?.close()
            }
        )
        // The window says how big the guide is. Left to size the window, the
        // hosting view holds it to the guide's full height whatever the
        // screen, and adds the title bar's, though the guide is drawn under
        // the title bar and not below it.
        guide.sizingOptions = []
        window.contentView = guide
        window.setContentSize(size)
        window.center()
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    /// Puts the guide up, or brings it forward at the page it is on.
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // Opened at login, Drag Timer is not the active app and may not be
        // made it, and a window ordered front the ordinary way stays behind
        // the active app's.
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    #if DEBUG
    var pageForTesting: WelcomePage {
        get { pager.page }
        set { pager.page = newValue }
    }
    #endif
}

/// The guide's window, which answers the keys that no one button in the
/// guide can: Esc shuts it, and ← and → turn its pages.
///
/// The window takes them itself, ahead of anything in it. Left to the guide
/// they worked only where a button carried them, and a key reached the
/// buttons one way in a window that had the keyboard and another in one
/// that did not: on the last page, which has Get Started and no Close, Esc
/// in the window as it really runs reached neither a hidden button in the
/// guide nor the window's controller behind it. Nothing in the guide takes
/// typing; a field added to it would want these keys back.
private final class WelcomeWindow: NSWindow {
    /// ← and →, as -1 and 1.
    var onArrow: (Int) -> Void = { _ in }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown,
              isVisible,
              event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else {
            return super.sendEvent(event)
        }
        switch Int(event.keyCode) {
        case kVK_Escape: close()
        case kVK_LeftArrow: onArrow(-1)
        case kVK_RightArrow: onArrow(1)
        default: super.sendEvent(event)
        }
    }
}

/// When the guide is put up, and what follows it.
final class WelcomePresenter {
    private let settings: AppSettings
    private let showTimers: () -> Void
    private var windowController: WelcomeWindowController?
    /// Set while the guide a first launch opened with is up.
    private var showsTimersWhenShut = false

    /// `showTimers` opens the popover.
    init(settings: AppSettings, showTimers: @escaping () -> Void) {
        self.settings = settings
        self.showTimers = showTimers
    }

    /// Opens with the guide if it has never been up on this Mac: a new
    /// menu-bar icon explains nothing by itself. On a first launch the
    /// popover follows the guide, which is what shows where in the menu bar
    /// the clock is. After an update the clock is where it always was.
    func offerAtLaunch() {
        guard !settings.hasSeenWelcome else { return }
        showsTimersWhenShut = settings.isFirstLaunch
        show()
    }

    /// Puts the guide up at its first page, or brings it forward as it is
    /// if it is up already.
    func show() {
        if windowController?.window?.isVisible != true {
            windowController = WelcomeWindowController { [weak self] in
                self?.guideDidClose()
            }
        }
        // Seen as soon as it is up, not when its last page is reached: a
        // guide that came back at every login until it had been read to the
        // end would be in the way.
        if !settings.hasSeenWelcome {
            settings.hasSeenWelcome = true
        }
        windowController?.show()
    }

    private func guideDidClose() {
        let showsTimers = showsTimersWhenShut
        showsTimersWhenShut = false
        // Once the window has gone, not while it is going.
        DispatchQueue.main.async { [weak self, showTimers] in
            // Most people see the guide once. Its window and seven pages of
            // drawings are not kept for the weeks the app then runs.
            if let self, self.windowController?.window?.isVisible != true {
                self.windowController = nil
            }
            if showsTimers { showTimers() }
        }
    }

    #if DEBUG
    var windowControllerForTesting: WelcomeWindowController? { windowController }
    #endif
}
