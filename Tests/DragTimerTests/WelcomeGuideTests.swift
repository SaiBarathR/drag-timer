import AppKit
import XCTest
@testable import DragTimer

final class WelcomeGuideTests: XCTestCase {
    func testEveryPageWithAPictureNumbersItsTipsFromOne() {
        for page in WelcomePage.allCases where page != .keys {
            // The picture's dots are numbered by hand, in this order.
            XCTAssertEqual(page.tips.map(\.id), Array(1...page.tips.count), "\(page)")
            // Two to a row: an odd one would sit beside an empty space.
            XCTAssertTrue(page.tips.count.isMultiple(of: 2), "\(page)")
            XCTAssertNotNil(page.place, "\(page)")
            XCTAssertFalse(page.regions.isEmpty, "\(page)")
        }
    }

    func testTheLastPageIsTheKeysAndHasNoPicture() {
        XCTAssertEqual(WelcomePage.allCases.last, .keys)
        XCTAssertTrue(WelcomePage.keys.tips.isEmpty)
        XCTAssertNil(WelcomePage.keys.place)
        XCTAssertTrue(WelcomePage.keys.regions.isEmpty)
    }

    func testShortcutsAreToldApartWithinTheirGroup() {
        let groups = WelcomeShortcutGroup.all
        XCTAssertEqual(Set(groups.map(\.id)).count, groups.count)
        for group in groups {
            XCTAssertFalse(group.shortcuts.isEmpty, group.title)
            XCTAssertEqual(Set(group.shortcuts.map(\.id)).count, group.shortcuts.count, group.title)
        }
    }

    func testChordsAreReadOutByName() {
        XCTAssertEqual(KeyCap.spoken(["⌘", "Z"]), "Command Z")
        XCTAssertEqual(KeyCap.spoken(["⇧", "↩"]), "Shift Return")
        XCTAssertEqual(KeyCap.spoken(["esc"]), "Escape")
        XCTAssertEqual(KeyCap.spoken(["→"]), "Right Arrow")
        XCTAssertEqual(KeyCap.spoken(["right-click"]), "right-click")
    }

    func testEveryKeyTheGuideDrawsHasANameToBeReadOut() {
        let chords = WelcomePage.allCases.flatMap(\.tips).flatMap(\.keys)
            + WelcomeShortcutGroup.all.flatMap(\.shortcuts).flatMap(\.keys)
        // A symbol with no name would be read as the symbol, or not at all.
        let symbols = Set(chords.joined()).filter { !$0.contains(where: \.isLetter) }
        for symbol in symbols {
            XCTAssertNotEqual(KeyCap.spoken([symbol]), symbol)
        }
    }

    func testNumbersTheGuideSpellsOutAreTheAppsOwn() {
        // The guide writes these into its sentences as words. Change one of
        // the app's and the sentence beside it here has to change with it.
        func text(_ page: WelcomePage, _ tip: Int) -> String { page.tips[tip - 1].text }

        let minute: TimeInterval = 60
        let hour: TimeInterval = 3_600
        let bands = Array(DurationLadder.bands.prefix(3))
        let upTo: [TimeInterval] = bands.map { $0.upperBound }
        let by: [TimeInterval] = bands.map { $0.step }
        XCTAssertEqual(upTo, [15 * minute, hour, 4 * hour])
        XCTAssertEqual(by, [minute, 5 * minute, 15 * minute])
        XCTAssertEqual(DragPhysicsSettings().maximumDuration, 4 * hour)
        XCTAssertTrue(text(.pull, 2).contains(
            "A minute at a time up to 15 minutes, then by 5 up to an hour and by 15 up to 4 hours."
        ))
        for minutes in [5, 15, 30] {
            XCTAssertTrue(SnapGrid.points.contains(TimeInterval(minutes * 60)), "\(minutes)")
        }
        XCTAssertTrue(text(.pull, 2).contains("such as 5, 15 and 30 minutes"))

        XCTAssertEqual(AppSettings.defaultQuickStartMinutes.count, 8)
        XCTAssertTrue(text(.quickStart, 2).contains("eight to begin with"))

        XCTAssertEqual(TimerEngine.undoWindow, 10)
        XCTAssertTrue(text(.running, 4).contains("For ten seconds"))

        XCTAssertEqual(UrgentThreshold.allCases.map(\.rawValue).max(), 10 * 60)
        XCTAssertTrue(text(.menuBar, 3).contains("In its last minute"))

        XCTAssertEqual(AppSettings.maximumPresetCount, 12)
        XCTAssertTrue(text(.preferences, 1).contains("Up to twelve"))

        XCTAssertEqual(AppSettings.maximumDragDurationHoursRange, 4...24)
        XCTAssertTrue(text(.preferences, 3).contains("from 4 hours up to 24"))

        XCTAssertEqual(TimerHistoryStore.retentionDays, 90)
        XCTAssertEqual(TimerHistoryStore(fileURL: URL(fileURLWithPath: "/dev/null")).maximumEntries, 500)
        XCTAssertTrue(text(.preferences, 4).contains("the last ninety days, up to 500"))
    }

    func testANewTimerTurnsRedInItsLastMinute() {
        let fixture = makeDefaults()
        defer { fixture.cleanup() }

        // "In its last minute", the guide says, of a Mac nobody has set up.
        XCTAssertEqual(AppSettings(defaults: fixture.defaults).urgentThreshold, .oneMinute)
    }

    func testTheGuideNamesWhatTheClocksMenuHolds() {
        let tip = WelcomePage.menuBar.tips[3].text

        // Its own entry is "this guide" there; the rest are by name.
        for title in WelcomeArt.clockMenu.compactMap({ $0 }) where title != "Welcome Guide" {
            XCTAssertTrue(tip.contains("**\(title)**"), title)
        }
    }

    func testGuideIsNoTallerThanItsScreenHasRoomFor() {
        XCTAssertEqual(WelcomeGuide.height(fitting: 1_050), WelcomeGuide.size.height)
        // A 13-inch MacBook at its largest text size, with the Dock showing.
        XCTAssertEqual(WelcomeGuide.height(fitting: 545), 545)
    }

    @MainActor
    func testGuideWindowIsTheSizeItsPagesAreLaidOutForWhereThatFits() {
        _ = NSApplication.shared
        let controller = WelcomeWindowController()
        defer { controller.close() }
        let size = NSSize(
            width: WelcomeGuide.size.width,
            height: WelcomeGuide.height(fitting: NSScreen.main?.visibleFrame.height ?? WelcomeGuide.size.height)
        )

        // Showing it is when a hosting view resizes its window, and it would
        // add the height of the title bar the guide is drawn under.
        controller.show()

        XCTAssertEqual(controller.window?.frame.size, size)
        XCTAssertEqual(controller.window?.contentView?.frame.size, size)
        XCTAssertEqual(controller.window?.title, "Welcome to Drag Timer")
    }

    // MARK: - Keys

    @MainActor
    func testArrowKeysAndReturnTurnThePages() {
        _ = NSApplication.shared
        let controller = WelcomeWindowController()
        defer { controller.close() }
        controller.show()

        press(.rightArrow, in: controller)
        XCTAssertEqual(controller.pageForTesting, .quickStart)
        XCTAssertTrue(pressReturn(in: controller) { controller.pageForTesting == .running })
        press(.leftArrow, in: controller)
        XCTAssertEqual(controller.pageForTesting, .quickStart)
    }

    @MainActor
    func testArrowKeysStopAtTheFirstAndLastPages() {
        _ = NSApplication.shared
        let controller = WelcomeWindowController()
        defer { controller.close() }
        controller.show()

        press(.leftArrow, in: controller)
        XCTAssertEqual(controller.pageForTesting, WelcomePage.allCases.first)

        controller.pageForTesting = .keys
        press(.rightArrow, in: controller)
        XCTAssertEqual(controller.pageForTesting, .keys)
        XCTAssertEqual(controller.window?.isVisible, true)
    }

    @MainActor
    func testEscapeShutsTheGuideOnEveryPage() {
        _ = NSApplication.shared
        let controller = WelcomeWindowController()
        defer { controller.close() }

        // The last page has no Close button; that is where Esc once did
        // nothing.
        for page in WelcomePage.allCases {
            controller.show()
            controller.pageForTesting = page

            press(.escape, in: controller)

            XCTAssertEqual(controller.window?.isVisible, false, "\(page)")
        }
    }

    @MainActor
    func testReturnOnTheLastPageIsGetStarted() {
        _ = NSApplication.shared
        let controller = WelcomeWindowController()
        defer { controller.close() }
        controller.show()
        controller.pageForTesting = .keys

        XCTAssertTrue(pressReturn(in: controller) { controller.window?.isVisible == false })
    }

    @MainActor
    func testKeysHeldWithAModifierAreNotTheGuides() {
        _ = NSApplication.shared
        let controller = WelcomeWindowController()
        defer { controller.close() }
        controller.show()

        // VoiceOver moves about with Control-Option and the arrows.
        press(.rightArrow, with: [.control, .option], in: controller)
        press(.escape, with: .command, in: controller)

        XCTAssertEqual(controller.pageForTesting, WelcomePage.allCases.first)
        XCTAssertEqual(controller.window?.isVisible, true)
    }

    // MARK: - Opening and shutting

    @MainActor
    func testEveryWayOfShuttingTheGuideIsReportedOnce() {
        _ = NSApplication.shared
        var closes = 0
        let controller = WelcomeWindowController { closes += 1 }

        controller.show()
        XCTAssertEqual(closes, 0)
        // The window's own close button.
        controller.window?.performClose(nil)
        XCTAssertEqual(closes, 1)

        // Esc.
        controller.show()
        press(.escape, in: controller)
        XCTAssertEqual(closes, 2)

        // Return on the last page, which is Get Started.
        controller.show()
        controller.pageForTesting = .keys
        XCTAssertTrue(pressReturn(in: controller) { closes >= 3 })

        // And a key that arrives once it has shut is not a second shutting.
        press(.escape, in: controller)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(closes, 3)
    }

    @MainActor
    func testGuideOpensByItselfOnceAndNeverAgain() {
        _ = NSApplication.shared
        let fixture = makeDefaults()
        defer { fixture.cleanup() }

        let settings = AppSettings(defaults: fixture.defaults)
        let presenter = WelcomePresenter(settings: settings, showTimers: {})
        defer { presenter.windowControllerForTesting?.close() }
        presenter.offerAtLaunch()

        XCTAssertEqual(presenter.windowControllerForTesting?.window?.isVisible, true)
        XCTAssertEqual(presenter.windowControllerForTesting?.pageForTesting, WelcomePage.allCases.first)
        XCTAssertTrue(settings.hasSeenWelcome)

        // The next launch, whether or not the guide was read to its end.
        let relaunched = WelcomePresenter(settings: AppSettings(defaults: fixture.defaults), showTimers: {})
        relaunched.offerAtLaunch()

        XCTAssertNil(relaunched.windowControllerForTesting)
    }

    @MainActor
    func testShuttingTheGuideOfAFirstLaunchShowsTheTimersOnce() {
        _ = NSApplication.shared
        let fixture = makeDefaults()
        defer { fixture.cleanup() }
        var timersShown = 0
        let presenter = WelcomePresenter(settings: AppSettings(defaults: fixture.defaults)) {
            timersShown += 1
        }
        defer { presenter.windowControllerForTesting?.close() }

        presenter.offerAtLaunch()
        XCTAssertEqual(timersShown, 0)
        presenter.windowControllerForTesting?.close()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(timersShown, 1)

        // Opened again from a menu, it is only a guide.
        presenter.show()
        XCTAssertEqual(presenter.windowControllerForTesting?.window?.isVisible, true)
        presenter.windowControllerForTesting?.close()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(timersShown, 1)
    }

    @MainActor
    func testAnUpdateIsShownTheGuideAndNotTheTimers() throws {
        _ = NSApplication.shared
        let fixture = makeDefaults()
        defer { fixture.cleanup() }
        // Settings from a version that had no guide.
        fixture.defaults.set(
            try JSONSerialization.data(withJSONObject: ["hapticsEnabled": false]),
            forKey: "DragTimer.AppSettings.v1"
        )
        var timersShown = 0
        let presenter = WelcomePresenter(settings: AppSettings(defaults: fixture.defaults)) {
            timersShown += 1
        }
        defer { presenter.windowControllerForTesting?.close() }

        presenter.offerAtLaunch()
        XCTAssertEqual(presenter.windowControllerForTesting?.window?.isVisible, true)

        presenter.windowControllerForTesting?.close()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(timersShown, 0)
    }

    @MainActor
    func testGuideOpenedFromAMenuDoesNotOpenByItselfLater() {
        _ = NSApplication.shared
        let fixture = makeDefaults()
        defer { fixture.cleanup() }
        let presenter = WelcomePresenter(settings: AppSettings(defaults: fixture.defaults), showTimers: {})
        defer { presenter.windowControllerForTesting?.close() }

        presenter.show()

        XCTAssertTrue(AppSettings(defaults: fixture.defaults).hasSeenWelcome)
    }

    @MainActor
    func testGuideThatIsAlreadyOpenKeepsItsPageAndItsWindow() {
        _ = NSApplication.shared
        let fixture = makeDefaults()
        defer { fixture.cleanup() }
        let presenter = WelcomePresenter(settings: AppSettings(defaults: fixture.defaults), showTimers: {})
        defer { presenter.windowControllerForTesting?.close() }

        presenter.show()
        let open = presenter.windowControllerForTesting
        open?.pageForTesting = .finished
        presenter.show()

        XCTAssertTrue(presenter.windowControllerForTesting === open)
        XCTAssertEqual(open?.pageForTesting, .finished)
    }

    @MainActor
    func testShutGuideOpensAtItsFirstPageAgain() {
        _ = NSApplication.shared
        let fixture = makeDefaults()
        defer { fixture.cleanup() }
        let presenter = WelcomePresenter(settings: AppSettings(defaults: fixture.defaults), showTimers: {})
        defer { presenter.windowControllerForTesting?.close() }

        // Asked for again at once, and again when the shutting has settled.
        for settles in [false, true] {
            presenter.show()
            presenter.windowControllerForTesting?.pageForTesting = .finished
            presenter.windowControllerForTesting?.close()
            if settles { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }

            presenter.show()

            XCTAssertEqual(presenter.windowControllerForTesting?.window?.isVisible, true)
            XCTAssertEqual(presenter.windowControllerForTesting?.pageForTesting, WelcomePage.allCases.first)
            presenter.windowControllerForTesting?.close()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
    }

    @MainActor
    func testShutGuideIsNotKept() {
        _ = NSApplication.shared
        let fixture = makeDefaults()
        defer { fixture.cleanup() }
        let presenter = WelcomePresenter(settings: AppSettings(defaults: fixture.defaults), showTimers: {})

        weak var window: NSWindow?
        autoreleasepool {
            presenter.show()
            window = presenter.windowControllerForTesting?.window
            XCTAssertNotNil(window)
            presenter.windowControllerForTesting?.close()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }

        XCTAssertNil(presenter.windowControllerForTesting)
        // Nor held by anything else: the window and its pages are gone.
        XCTAssertNil(window)
    }

    private func makeDefaults() -> (defaults: UserDefaults, cleanup: () -> Void) {
        let suite = "DragTimerWelcomeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    private enum Key {
        case rightArrow, leftArrow, `return`, escape

        var code: UInt16 {
            switch self {
            case .rightArrow: return 124
            case .leftArrow: return 123
            case .return: return 36
            case .escape: return 53
            }
        }

        var characters: String {
            switch self {
            case .rightArrow: return String(UnicodeScalar(NSRightArrowFunctionKey)!)
            case .leftArrow: return String(UnicodeScalar(NSLeftArrowFunctionKey)!)
            case .return: return "\r"
            case .escape: return "\u{1B}"
            }
        }

        /// What the keyboard sets on the key by itself.
        var modifiers: NSEvent.ModifierFlags {
            switch self {
            case .rightArrow, .leftArrow: return [.function, .numericPad]
            case .return, .escape: return []
            }
        }
    }

    /// Return is a button's key, and a guide that has only just been put up
    /// or turned to a page has not drawn its buttons yet: a key that finds
    /// none is dropped, not kept. So it is pressed until it has done what it
    /// is for, and never again once it has.
    @MainActor
    private func pressReturn(in controller: WelcomeWindowController, until done: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while !done(), Date() < deadline {
            press(.return, in: controller)
            let nextPress = Date().addingTimeInterval(0.25)
            while !done(), Date() < nextPress {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
        }
        return done()
    }

    /// A key as the keyboard sends it, through the application as a real
    /// one goes.
    @MainActor
    private func press(
        _ key: Key,
        with held: NSEvent.ModifierFlags = [],
        in controller: WelcomeWindowController
    ) {
        guard let window = controller.window,
              let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: key.modifiers.union(held),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: key.characters,
                charactersIgnoringModifiers: key.characters,
                isARepeat: false,
                keyCode: key.code
              ) else {
            return XCTFail("no key event")
        }
        NSApp.sendEvent(event)
    }
}
