import AppKit
import SwiftUI

/// One page of the guide: a part of the app, where it is on screen, and what
/// can be done there.
enum WelcomePage: Int, CaseIterable, Identifiable {
    case pull, quickStart, running, finished, menuBar, preferences, keys

    var id: Int { rawValue }

    /// What the page is called in the list of them.
    var title: String {
        switch self {
        case .pull: return "Pull Out a Timer"
        case .quickStart: return "Quick Start"
        case .running: return "Running Timers"
        case .finished: return "When a Timer Ends"
        case .menuBar: return "In the Menu Bar"
        case .preferences: return "Make It Yours"
        case .keys: return "Keys and Clicks"
        }
    }

    var symbol: String {
        switch self {
        case .pull: return "hand.draw.fill"
        case .quickStart: return "bolt.fill"
        case .running: return "timer"
        case .finished: return "bell.fill"
        case .menuBar: return "menubar.rectangle"
        case .preferences: return "slider.horizontal.3"
        case .keys: return "keyboard.fill"
        }
    }

    /// The color of the page's symbol in the list, and of its picture.
    var tint: Color {
        switch self {
        case .pull: return .blue
        case .quickStart: return .orange
        case .running: return .green
        case .finished: return .red
        case .menuBar: return .purple
        case .preferences: return .teal
        case .keys: return .gray
        }
    }

    var headline: String {
        switch self {
        case .pull: return "Pull a timer out of the menu bar"
        case .quickStart: return "Quick start: a click instead of a drag"
        case .running: return "Running timers: pause, change, stop"
        case .finished: return "When a timer ends"
        case .menuBar: return "The menu bar: what the clock shows"
        case .preferences: return "Make it yours"
        case .keys: return "Keys and clicks"
        }
    }

    var lead: String {
        switch self {
        case .pull:
            return "Drag Timer is the small clock in the menu bar. It has no Dock "
                + "icon and no main window: press the clock, drag away from it, "
                + "and let go."
        case .quickStart:
            return "Click the clock and a panel opens under it. The lengths you use "
                + "most are at its top, with a field for any other length or a "
                + "time of day."
        case .running:
            return "Each timer has a row in the panel, counting down. The buttons on "
                + "the row are what is wanted most; everything else is under ⋯."
        case .finished:
            return "It plays its sound, shows a notification if those are allowed, "
                + "and stays in the menu bar until it is answered. One you missed "
                + "is still there when you look."
        case .menuBar:
            return "The clock is all there is to see of the app, so what it shows is "
                + "yours to choose. A right-click on it reaches everything else."
        case .preferences:
            return "The sliders button at the foot of the panel opens Preferences, "
                + "and the button beside it opens History. Both are on the clock’s "
                + "right-click menu as well."
        case .keys:
            return "There are not many. The keys and clicks that are Drag Timer’s "
                + "own, in one place."
        }
    }

    /// Where on screen the page is about, in words, for under the map of it.
    /// Nil for a page that is about no one part.
    var place: String? {
        switch self {
        case .pull: return "The clock in the menu bar"
        case .quickStart: return "The top of the panel"
        case .running: return "The rest of the panel"
        case .finished: return "The clock, and the panel"
        case .menuBar: return "The clock in the menu bar"
        case .preferences: return "Windows of their own"
        case .keys: return nil
        }
    }

    /// The parts of the screen lit on the map beside the heading.
    var regions: Set<ScreenMap.Region> {
        switch self {
        case .pull: return [.clock, .pull]
        case .quickStart: return [.presets]
        case .running: return [.list, .foot]
        case .finished: return [.clock, .list]
        case .menuBar: return [.clock]
        case .preferences: return [.foot, .window]
        case .keys: return []
        }
    }

    /// What can be done there, numbered as the picture numbers them.
    var tips: [WelcomeTip] {
        switch self {
        case .pull:
            return [
                WelcomeTip(
                    1, "Press the clock and pull",
                    "Hold the mouse button down on the clock and drag away from "
                        + "it. A line follows the pointer. A click, with no drag, "
                        + "opens the timers instead."
                ),
                WelcomeTip(
                    2, "Farther is longer",
                    "A minute at a time up to 15 minutes, then by 5 up to an "
                        + "hour and by 15 up to 4 hours. At round lengths such "
                        + "as 5, 15 and 30 minutes the line catches and turns "
                        + "green."
                ),
                WelcomeTip(
                    3, "The label says what you get",
                    "The length, and the time it will ring. Back on the clock it "
                        + "reads **Cancel**: let go there, or press Esc while "
                        + "still holding, and no timer starts.",
                    keys: [["esc"]]
                ),
                WelcomeTip(
                    4, "Let go, and name it",
                    "The timer starts as you let go. A prompt then offers to "
                        + "name it: Return saves the name, Esc leaves the timer "
                        + "as it is, and **Discard Timer** removes it.",
                    keys: [["↩"], ["esc"]]
                ),
            ]
        case .quickStart:
            return [
                WelcomeTip(
                    1, "Click the clock",
                    "A click opens the panel, and a click anywhere outside it "
                        + "shuts it again."
                ),
                WelcomeTip(
                    2, "Quick start",
                    "Each button starts a timer of that length at once. There "
                        + "are eight to begin with; Preferences ▸ Presets "
                        + "renames, recolors, reorders and replaces them."
                ),
                WelcomeTip(
                    3, "Any length, or a time of day",
                    "**Other length or time…** reads `25m`, `90s` and `1:30`, "
                        + "and a time of day as `@3:30pm` or `until 4`. The "
                        + "button says what it read, and Return starts it.",
                    keys: [["↩"]]
                ),
                WelcomeTip(
                    4, "Routines",
                    "A routine starts several timers at once: the stages of a "
                        + "Pomodoro, or of a morning. They appear here once one "
                        + "is made in Preferences ▸ Routines."
                ),
            ]
        case .running:
            return [
                WelcomeTip(
                    1, "Finish early",
                    "The checkmark marks a timer done. It goes into History as "
                        + "completed, and never rings."
                ),
                WelcomeTip(
                    2, "Pause, and carry on",
                    "Pause holds a timer where it is, and play starts it again. "
                        + "A paused row has Reset and Delete as well."
                ),
                WelcomeTip(
                    3, "Everything else, under ⋯",
                    "**Add 1 min** and **Subtract 1 min** move the end. **Edit "
                        + "timer** changes the name, color, symbol, sound and "
                        + "time left. **Reset timer** starts it over."
                ),
                WelcomeTip(
                    4, "Stop all, and Undo",
                    "**Stop all** cancels every timer in the list. For ten "
                        + "seconds after it, or after cancelling or finishing "
                        + "one early, the panel offers **Undo**, and the timers "
                        + "come back with the end times they had.",
                    keys: [["⌘", "Z"]]
                ),
            ]
        case .finished:
            return [
                WelcomeTip(
                    1, "The clock turns red",
                    "It fills red, and where it showed a countdown it counts "
                        + "up from the moment the timer ended, as `+2:15`, ahead "
                        + "of any timer still running."
                ),
                WelcomeTip(
                    2, "Answer it",
                    "**Snooze** runs it for its snooze length, and **Restart** "
                        + "for its whole length again. **Mark done** finishes "
                        + "it, and Return does the same.",
                    keys: [["↩"]]
                ),
                WelcomeTip(
                    3, "Quiet it first",
                    "The speaker button stops the sound and leaves the timer "
                        + "waiting for its answer."
                ),
                WelcomeTip(
                    4, "From the notification",
                    "The notification carries the same three choices. macOS "
                        + "asks whether to allow notifications when the first "
                        + "timer starts; Preferences ▸ General shows the answer."
                ),
            ]
        case .menuBar:
            return [
                WelcomeTip(
                    1, "The time left",
                    "To begin with it shows the countdown of the timer that "
                        + "ends soonest, and the clock takes that timer’s color "
                        + "and symbol."
                ),
                WelcomeTip(
                    2, "Or something else",
                    "Preferences ▸ Menu bar has **Count**, how many are "
                        + "running; **Pinned**, the timer chosen with **Pin to "
                        + "menu bar** under ⋯; and **Ring**, a ring that fills, "
                        + "with no digits."
                ),
                WelcomeTip(
                    3, "Nearly up",
                    "In its last minute a timer turns red and shows an "
                        + "exclamation mark. Preferences ▸ Appearance can "
                        + "start that earlier, or turn it off."
                ),
                WelcomeTip(
                    4, "Right-click the clock",
                    "**Show Timers**, **Timer History**, **Settings…**, this "
                        + "guide, and **Quit Drag Timer**.",
                    keys: [["right-click"]]
                ),
            ]
        case .preferences:
            return [
                WelcomeTip(
                    1, "Presets and routines",
                    "Up to twelve Quick start buttons, each with its own name, "
                        + "length, color, symbol and sound, and routines that "
                        + "start several timers together."
                ),
                WelcomeTip(
                    2, "How a timer ends",
                    "General sets what a new timer starts with: its sound and "
                        + "volume, whether it loops until stopped, and whether "
                        + "its name is said aloud. **Launch at login** is "
                        + "there too."
                ),
                WelcomeTip(
                    3, "Feel",
                    "**Precise** and **Snappy** start exactly the length shown. "
                        + "**Throwable** lets a moving release carry on past "
                        + "the pointer. The longest drag can go from 4 hours "
                        + "up to 24."
                ),
                WelcomeTip(
                    4, "History",
                    "Finished and cancelled timers from the last ninety days, "
                        + "up to 500 of them, kept on this Mac and nowhere else. "
                        + "**Again** starts one over."
                ),
            ]
        case .keys:
            return []
        }
    }
}

/// One thing that can be done on a page, and the keys for it.
struct WelcomeTip: Identifiable {
    /// Its number on the page, which is its number on the picture.
    let id: Int
    let title: String
    /// Markdown: `**bold**` for what a control is called on screen, and
    /// backticks for something to type.
    let text: String
    /// Each of these is one key or one chord: `["⌘", "Z"]`.
    let keys: [[String]]

    init(_ id: Int, _ title: String, _ text: String, keys: [[String]] = []) {
        self.id = id
        self.title = title
        self.text = text
        self.keys = keys
    }
}

/// A line of the last page: the keys, and what they do.
struct WelcomeShortcut: Identifiable {
    let keys: [[String]]
    let action: String

    var id: String { action }

    init(_ keys: [[String]], _ action: String) {
        self.keys = keys
        self.action = action
    }
}

/// The shortcuts under one heading.
struct WelcomeShortcutGroup: Identifiable {
    let title: String
    let shortcuts: [WelcomeShortcut]

    var id: String { title }

    /// The keys and the kinds of click that are the app's own, in the order
    /// someone would come to need them; Copy, Paste and the rest of the Edit
    /// menu's are every app's. A menu-bar app has no menus to list its keys
    /// in, so this is the only place they are all written down.
    static let all: [WelcomeShortcutGroup] = [
        WelcomeShortcutGroup(
            title: "The clock",
            shortcuts: [
                WelcomeShortcut([["click"]], "Open the panel, or shut it"),
                WelcomeShortcut([["drag"]], "Pull out a timer"),
                WelcomeShortcut([["right-click"]], "History, Settings, this guide and Quit"),
            ]
        ),
        WelcomeShortcutGroup(
            title: "While dragging",
            shortcuts: [
                WelcomeShortcut([["esc"]], "Let go of the drag: no timer starts"),
            ]
        ),
        WelcomeShortcutGroup(
            title: "Naming a timer",
            shortcuts: [
                WelcomeShortcut([["↩"]], "Save the name"),
                WelcomeShortcut([["⇧", "↩"]], "Add a line to the name"),
                WelcomeShortcut([["esc"]], "Keep the timer, under the name it has"),
            ]
        ),
        WelcomeShortcutGroup(
            title: "In the panel",
            shortcuts: [
                WelcomeShortcut([["↩"]], "Mark a finished timer done"),
                WelcomeShortcut([["⌘", "Z"]], "Undo Stop all, or a timer cancelled or finished early"),
            ]
        ),
        WelcomeShortcutGroup(
            title: "Typing a length",
            shortcuts: [
                WelcomeShortcut([["↩"]], "Start the length or time typed"),
                WelcomeShortcut([["esc"]], "Put the field away"),
            ]
        ),
        WelcomeShortcutGroup(
            title: "This guide",
            shortcuts: [
                WelcomeShortcut([["→"], ["←"]], "Turn its pages"),
                WelcomeShortcut([["↩"]], "The next page, or Get Started on the last"),
                WelcomeShortcut([["esc"]], "Shut it"),
            ]
        ),
    ]
}

/// Which page the guide is open at. Held outside the view because the
/// window turns the pages too: ← and → are its keys.
final class WelcomePager: ObservableObject {
    @Published var page = WelcomePage.allCases[0]

    /// Turns on a page, or with -1 back one. At either end it stays put.
    func step(_ by: Int) {
        guard let next = WelcomePage(rawValue: page.rawValue + by) else { return }
        page = next
    }
}

/// The guide to the app: what it is for, where each thing is, and the keys.
///
/// Put up the first time the app is opened, and from the clock's right-click
/// menu after that. A menu-bar app shows a new user one small icon, and
/// nothing on screen gives away that the icon can be dragged, that Escape
/// lets go of a drag, or that a typed length can be a time of day. It was
/// all in a README.
struct WelcomeGuide: View {
    @ObservedObject var pager: WelcomePager
    let onClose: () -> Void

    /// The size its pages are laid out for: each fits without scrolling.
    static let size = CGSize(width: 900, height: 620)

    /// That height, or what the screen has room for. A MacBook at its
    /// largest text size has less than 620 points between the menu bar and
    /// the Dock, and the window cannot be resized: its foot, where the
    /// buttons are, would be under the Dock. Shorter, the page scrolls.
    static func height(fitting available: CGFloat) -> CGFloat {
        min(size.height, available)
    }

    private var page: WelcomePage { pager.page }

    var body: some View {
        // The window's title bar is clear and lies over the top of the
        // guide, with its close button over the list of pages. Its height
        // is read here, before the guide is laid out under it, for the two
        // things that have to start below it.
        GeometryReader { window in
            let titleBar = window.safeAreaInsets.top
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    sidebar(under: titleBar)
                        .frame(width: 216)
                    Divider()
                    WelcomePageView(page: page, titleBar: titleBar)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // A new page starts at its top, not where the last
                        // was scrolled to.
                        .id(page)
                }
                Divider()
                footer
            }
            .ignoresSafeArea()
        }
        .frame(width: Self.size.width)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }

    // MARK: - The list of pages

    private func sidebar(under titleBar: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 54, height: 54)
                    .accessibilityHidden(true)
                Text("Welcome to Drag Timer")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.top, 4)
                Text("What it is for, and how to use it")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, titleBar + 8)
            .padding(.bottom, 14)

            VStack(spacing: 2) {
                ForEach(WelcomePage.allCases) { entry in
                    pageButton(entry)
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 0)

            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text("Drag Timer \(version)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(16)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.04))
    }

    private func pageButton(_ entry: WelcomePage) -> some View {
        let isCurrent = entry == page
        return Button {
            pager.page = entry
        } label: {
            HStack(spacing: 8) {
                Image(systemName: entry.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6).fill(entry.tint.gradient)
                    )
                    .accessibilityHidden(true)
                Text(entry.title)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isCurrent ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    // MARK: - The foot of it

    private var isLastPage: Bool { page == WelcomePage.allCases.last }

    private var footer: some View {
        HStack(spacing: 10) {
            // Said, not left to be found: the guide opens by itself only
            // once, and this is what makes it safe to shut.
            Label("This guide stays on the clock’s right-click menu.", systemImage: "cursorarrow.click.2")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(page.rawValue + 1) of \(WelcomePage.allCases.count)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)

            // Return is whichever button is drawn as the default. Esc, ←
            // and → have no button that is on every page to carry them, and
            // are the window's to answer.
            Button("Back") { pager.step(-1) }
                .disabled(page == WelcomePage.allCases.first)

            if isLastPage {
                Button("Get Started") { onClose() }
                    .keyboardShortcut(.defaultAction)
            } else {
                // Esc and Return are both a way out of a dialog, and Return
                // here turns the page: Esc is the one that shuts it.
                Button("Close") { onClose() }
                Button("Next") { pager.step(1) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// What one page says: a picture of the part of the app it is about, where
/// that is, and the things to do there.
struct WelcomePageView: View {
    let page: WelcomePage
    /// How much of the top of the page the window's title bar lies over.
    var titleBar: CGFloat = 0

    /// The tips two to a row.
    private var rows: [[WelcomeTip]] {
        let tips = page.tips
        return stride(from: 0, to: tips.count, by: 2).map { start in
            Array(tips[start..<min(start + 2, tips.count)])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if page == .keys {
                    heading
                    WelcomeShortcutsTable()
                } else {
                    WelcomeArt(page: page)
                        .frame(height: WelcomeArt.height)
                    heading
                    Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                        ForEach(rows, id: \.first?.id) { row in
                            GridRow {
                                ForEach(row) { tip in
                                    WelcomeTipCard(tip: tip)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            // A picture can run up under the title bar, which is clear. The
            // last page has none, and its heading starts below it.
            .padding(.top, page == .keys ? max(18, titleBar + 6) : 18)
            .padding(.bottom, 18)
        }
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(page.headline)
                    .font(.system(size: 21, weight: .semibold))
                Text(page.lead)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let place = page.place {
                VStack(spacing: 4) {
                    ScreenMap(lit: page.regions)
                    Text(place)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: 112)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Where it is: " + place)
            }
        }
    }
}

/// One thing to do, under the number the picture points at it with.
struct WelcomeTipCard: View {
    let tip: WelcomeTip

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            GuideBadge(number: tip.id)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Text(tip.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                    Spacer(minLength: 0)
                    if !tip.keys.isEmpty {
                        KeyRow(keys: tip.keys).fixedSize()
                    }
                }
                Text(LocalizedStringKey(tip.text))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        // As tall as the card beside it, whichever of the two has more to say.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08))
        )
    }
}

/// Every key and click, under the heading of what it is for.
struct WelcomeShortcutsTable: View {
    /// Two columns of about the same length.
    private var halves: [[WelcomeShortcutGroup]] {
        let groups = WelcomeShortcutGroup.all
        return [Array(groups.prefix(3)), Array(groups.dropFirst(3))]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(Array(halves.enumerated()), id: \.offset) { half in
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(half.element) { group in
                        section(group)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func section(_ group: WelcomeShortcutGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.bottom, 5)
            VStack(spacing: 0) {
                ForEach(Array(group.shortcuts.enumerated()), id: \.element.id) { entry in
                    if entry.offset > 0 { Divider() }
                    line(entry.element)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08))
            )
        }
    }

    private func line(_ shortcut: WelcomeShortcut) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(shortcut.action)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            KeyRow(keys: shortcut.keys)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
    }
}

/// Keys and chords in a row: `⌘ Z`, or `→  ←`.
struct KeyRow: View {
    let keys: [[String]]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(keys.enumerated()), id: \.offset) { chord in
                HStack(spacing: 2) {
                    ForEach(Array(chord.element.enumerated()), id: \.offset) { key in
                        KeyCap(label: key.element)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(KeyCap.spoken(chord.element))
            }
        }
    }
}

/// One key, drawn as the top of one.
struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 19)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.22))
            )
            .shadow(color: .black.opacity(0.14), radius: 0, y: 1)
    }

    /// The names of the keys the symbols stand for, for being read out.
    static func spoken(_ chord: [String]) -> String {
        chord.map { key in
            switch key {
            case "⌘": return "Command"
            case "⇧": return "Shift"
            case "↩": return "Return"
            case "→": return "Right Arrow"
            case "←": return "Left Arrow"
            case "esc": return "Escape"
            default: return key
            }
        }
        .joined(separator: " ")
    }
}

/// A numbered dot: on a picture, and on the card that says what it is
/// pointing at.
struct GuideBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 17, height: 17)
            .background(Circle().fill(Color.accentColor))
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            .accessibilityHidden(true)
    }
}

/// The screen, drawn small, with the part a page is about lit: the menu bar
/// with the clock in it, the panel that opens under the clock, and a window
/// for Preferences and History.
///
/// The app has no window of its own to draw a map of. Where a thing is means
/// where on the screen it turns up.
struct ScreenMap: View {
    enum Region: Hashable {
        case clock, pull, presets, list, foot, window
    }

    let lit: Set<Region>

    private static let clockCenter = CGPoint(x: 83.5, y: 3)
    private static let pullEnd = CGPoint(x: 60, y: 37)

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The menu bar, with the clock towards its right-hand end.
            block(nil, CGRect(x: 0, y: 0, width: 77, height: 6))
            Circle()
                .fill(fill(.clock))
                .frame(width: 7, height: 7)
                .offset(x: Self.clockCenter.x - 3.5, y: -0.5)
            block(nil, CGRect(x: 90, y: 0, width: 12, height: 6))

            block(.window, CGRect(x: 4, y: 14, width: 44, height: 31))

            if lit.contains(.pull) {
                // No panel: a drag starts from the clock with nothing open.
                Path { path in
                    path.move(to: Self.clockCenter)
                    path.addLine(to: Self.pullEnd)
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
                    .offset(x: Self.pullEnd.x - 3.5, y: Self.pullEnd.y - 3.5)
            } else {
                block(.presets, CGRect(x: 66, y: 10, width: 35, height: 11))
                block(.list, CGRect(x: 66, y: 23, width: 35, height: 17))
                block(.foot, CGRect(x: 66, y: 42, width: 35, height: 7))
            }
        }
        .frame(width: 102, height: 50, alignment: .topLeading)
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.18)))
    }

    private func block(_ region: Region?, _ rect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(fill(region))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }

    private func fill(_ region: Region?) -> Color {
        guard let region, lit.contains(region) else { return Color.primary.opacity(0.13) }
        return Color.accentColor
    }
}
