import AppKit
import SwiftUI

/// The picture at the head of a page of the guide: the part of the app the
/// page is about, drawn small, with a numbered dot on each thing the cards
/// below it go on to explain.
///
/// Drawn, not photographed. A screenshot is a file to ship and to keep up
/// with the app, shows one appearance, and is somebody's menu bar.
struct WelcomeArt: View {
    let page: WelcomePage

    static let height: CGFloat = 184

    /// The clock's right-click menu as its picture draws it, with nil for
    /// the line between two groups. A test holds it to the menu itself.
    static let clockMenu: [String?] = [
        "Show Timers", "Timer History", "Settings…", nil,
        "Welcome Guide", nil, "Quit Drag Timer",
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                picture(in: geometry.size)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .background(
            LinearGradient(
                colors: [page.tint.opacity(0.34), page.tint.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        // A panel that carries on past the edge of its picture is cut off
        // there, which is how a picture shows only the top or the foot of it.
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // The cards say all of it in words.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func picture(in size: CGSize) -> some View {
        switch page {
        case .pull: PullArt(size: size)
        case .quickStart: QuickStartArt(size: size)
        case .running: RunningArt()
        case .finished: FinishedArt(size: size)
        case .menuBar: MenuBarArt(size: size)
        case .preferences: PreferencesArt(size: size)
        case .keys: EmptyView()
        }
    }
}

extension View {
    /// Pins a numbered dot to an edge or a corner of something in a picture.
    /// `outset` is how far out from there its near side starts: half its own
    /// width puts it half on and half off, and all of it puts it clear of
    /// something too small to have a dot on top of it.
    func guideBadge(
        _ number: Int,
        at alignment: Alignment = .topTrailing,
        outset: CGFloat = 8
    ) -> some View {
        let across: CGFloat =
            alignment.horizontal == .trailing
            ? outset : (alignment.horizontal == .leading ? -outset : 0)
        let down: CGFloat =
            alignment.vertical == .top
            ? -outset : (alignment.vertical == .bottom ? outset : 0)
        return overlay(alignment: alignment) {
            GuideBadge(number: number).offset(x: across, y: down)
        }
    }

    /// The back of a window, a panel or a prompt.
    fileprivate func artCard(radius: CGFloat = 9) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.primary.opacity(0.14)))
        .shadow(color: .black.opacity(0.2), radius: 9, y: 4)
    }
}

// MARK: - Parts the pictures share

/// The timers the pictures are of, so that the tea on one page is the tea on
/// the next.
private enum ArtSample {
    static let tea = TimerIdentity(color: .amber, symbolName: "cup.and.saucer.fill")
    static let standUp = TimerIdentity(color: .blue, symbolName: "briefcase.fill")
    static let focus = TimerIdentity(color: .violet, symbolName: "book.fill")
    static let laundry = TimerIdentity(color: .mint, symbolName: "washer.fill")

    /// A time of day as the app writes one, so a picture reads 15:45 on a
    /// Mac that is set to a 24-hour clock.
    static func time(_ hour: Int, _ minute: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())
        return TimerDateText.fireTime(for: date ?? Date())
    }
}

/// A line of small type, as most of the app is set in.
private func artText(
    _ text: String,
    _ style: HierarchicalShapeStyle = .primary,
    size: CGFloat = 10
) -> some View {
    Text(text)
        .font(.system(size: size).monospacedDigit())
        .foregroundStyle(style)
        .lineLimit(1)
}

/// The heading over a part of the panel.
private func artCaption(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 8.5, weight: .semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
}

/// A push button, as the app draws them.
private struct ArtButton: View {
    let title: String
    var isProminent = false
    var isDestructive = false
    /// As wide as it is given room to be, where it shares a row equally.
    var fills = false

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(isProminent ? Color.white : (isDestructive ? Color.red : Color.primary))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(maxWidth: fills ? .infinity : nil)
            .frame(height: 18)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isProminent ? Color.accentColor : Color.primary.opacity(0.12))
            )
    }
}

/// One of the borderless buttons at the end of a row or the foot of the panel.
private struct ArtSymbolButton: View {
    let symbol: String
    var color = Color.primary

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 20, height: 20)
    }
}

/// The clock, as the menu bar draws it.
private struct ArtClock: View {
    enum Face {
        /// Two hands: no timer is running.
        case hands
        /// The running timer's own symbol.
        case symbol(String)
        case exclamation
    }

    var face = Face.hands
    var color = Color.primary
    /// Filled, as it is for a timer that has ended.
    var isFilled = false
    /// How much of the ring round it is drawn, where the menu bar is set to
    /// Ring.
    var ring: Double?

    var body: some View {
        ZStack {
            Circle().stroke(color, lineWidth: 1.6)
            if isFilled { Circle().fill(color) }
            switch face {
            case .hands:
                Path { path in
                    path.move(to: CGPoint(x: 7, y: 7))
                    path.addLine(to: CGPoint(x: 7, y: 3))
                    path.move(to: CGPoint(x: 7, y: 7))
                    path.addLine(to: CGPoint(x: 10.2, y: 8.8))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            case let .symbol(name):
                Image(systemName: name)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(color)
            case .exclamation:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isFilled ? Color.white : color)
            }
            if let ring {
                Circle()
                    .stroke(Color.primary.opacity(0.2), lineWidth: 1.8)
                    .padding(-2.5)
                Circle()
                    .trim(from: 0, to: ring)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(-2.5)
            }
        }
        .frame(width: 14, height: 14)
    }
}

/// The clock in the menu bar with the digits beside it. Laid out from the
/// middle of the clock, which is where a drag starts and where the panel's
/// arrow points.
private struct ArtStatusItem: View {
    var clock = ArtClock()
    var text: String?
    var textColor = Color.primary
    /// Held down, as it is for the length of a drag.
    var isPressed = false

    var body: some View {
        clock
            .background {
                if isPressed {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor.opacity(0.3))
                        .frame(width: 28, height: 19)
                }
            }
            .overlay(alignment: .leading) {
                if let text {
                    Text(text)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(textColor)
                        .fixedSize()
                        .offset(x: 20)
                }
            }
    }
}

/// The menu bar across the top of a picture. Other apps' menus and icons are
/// blanks: the clock is the only thing in it that is anyone's business here,
/// and a page puts it where it wants it.
private struct ArtMenuBar: View {
    static let height: CGFloat = 22

    var body: some View {
        HStack(spacing: 9) {
            blank(11)
            blank(36)
            blank(22)
            blank(24)
            blank(30)
            Spacer()
            blank(13)
            blank(13)
            blank(46)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.62))
        .overlay(alignment: .bottom) {
            Color.primary.opacity(0.1).frame(height: 0.5)
        }
    }

    private func blank(_ width: CGFloat) -> some View {
        Capsule()
            .fill(Color.primary.opacity(0.16))
            .frame(width: width, height: 5)
    }
}

/// The outline of the panel that opens under the clock: a rounded box with
/// its arrow on top.
private struct ArtPanelShape: Shape {
    static let arrowHeight: CGFloat = 7

    /// How far along the top edge the arrow is.
    let arrowX: CGFloat

    func path(in rect: CGRect) -> Path {
        let top = rect.minY + Self.arrowHeight
        let radius: CGFloat = 9
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: top))
        path.addLine(to: CGPoint(x: rect.minX + arrowX - 8, y: top))
        path.addLine(to: CGPoint(x: rect.minX + arrowX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + arrowX + 8, y: top))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: top),
            tangent2End: CGPoint(x: rect.maxX, y: rect.maxY),
            radius: radius
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY),
            radius: radius
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: top),
            radius: radius
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: top),
            tangent2End: CGPoint(x: rect.maxX, y: top),
            radius: radius
        )
        path.closeSubpath()
        return path
    }
}

/// The panel under the clock, from its arrow down.
private struct ArtPanel<Content: View>: View {
    let arrowX: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.top, ArtPanelShape.arrowHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                ArtPanelShape(arrowX: arrowX)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(ArtPanelShape(arrowX: arrowX).stroke(Color.primary.opacity(0.14)))
            .shadow(color: .black.opacity(0.2), radius: 9, y: 4)
    }
}

/// A Quick start button.
private struct ArtPreset: View {
    let title: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.blue)
            Text(title)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 17)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.1)))
    }
}

/// The Quick start buttons a new install has, as many rows of them as asked
/// for.
private struct ArtPresetGrid: View {
    var rows = 2

    private var titles: [String] {
        AppSettings.defaultQuickStartMinutes.map { DurationText.planned(TimeInterval($0 * 60)) }
    }

    var body: some View {
        Grid(horizontalSpacing: 5, verticalSpacing: 4) {
            ForEach(0..<rows, id: \.self) { row in
                GridRow {
                    ForEach(titles.dropFirst(row * 4).prefix(4), id: \.self) { title in
                        ArtPreset(title: title)
                    }
                }
            }
        }
    }
}

/// A timer's row in the panel, with the buttons at the end of it.
private struct ArtTimerRow<Buttons: View>: View {
    let name: String
    let detail: String
    let identity: TimerIdentity
    var progress = 0.4
    var isPaused = false
    @ViewBuilder var buttons: Buttons

    private var color: Color { isPaused ? .secondary : identity.color.color }

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().stroke(identity.color.color.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: isPaused ? "pause.fill" : identity.symbolName)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(color)
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 2) { buttons }
        }
        .padding(.horizontal, 14)
    }
}

/// A menu, open. A nil item is the line between two groups.
private struct ArtMenu: View {
    let items: [String?]
    var highlighted: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { entry in
                if let title = entry.element {
                    Text(title)
                        .font(.system(size: 10))
                        .foregroundStyle(title == highlighted ? Color.white : Color.primary)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 15, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(title == highlighted ? Color.accentColor : Color.clear)
                        )
                } else {
                    Divider()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                }
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.18)))
        .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
    }
}

/// A window, under its title bar.
private struct ArtWindow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 4) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { color in
                        Circle()
                            .fill(color.opacity(0.85))
                            .frame(width: 6, height: 6)
                    }
                    Spacer()
                }
                .padding(.leading, 7)
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 18)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .artCard()
    }
}

// MARK: - The pictures

/// A drag in flight: the line from the clock to the pointer, the label that
/// follows it, and the prompt that comes up when it is let go.
private struct PullArt: View {
    let size: CGSize

    private var clock: CGPoint {
        CGPoint(x: size.width * 0.66, y: ArtMenuBar.height / 2)
    }

    private var pointer: CGPoint {
        CGPoint(x: size.width * 0.28, y: 98)
    }

    var body: some View {
        ArtMenuBar()
        ArtStatusItem(isPressed: true)
            .position(clock)
        ArtPullLine(start: clock, end: pointer, size: size)
        GuideBadge(number: 1)
            .position(x: clock.x + 26, y: clock.y + 5)
        GuideBadge(number: 2)
            .position(rulerBadge)
        label
            .guideBadge(3)
            .position(x: pointer.x, y: pointer.y + 49)
        prompt
            .guideBadge(4)
            .frame(width: 196)
            .position(x: size.width - 116, y: 103)
    }

    /// Beside the ruler, half-way along it, on the side the label is not.
    private var rulerBadge: CGPoint {
        let dx = pointer.x - clock.x
        let dy = pointer.y - clock.y
        let length = hypot(dx, dy)
        return CGPoint(
            x: clock.x + dx * 0.5 - dy / length * 17,
            y: clock.y + dy * 0.5 + dx / length * 17
        )
    }

    private var label: some View {
        VStack(spacing: 1) {
            Text("15m")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("at \(ArtSample.time(15, 45))")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(.horizontal, 17)
        .frame(height: 42)
        // The label is this dark whatever the appearance: it is drawn over
        // whatever happens to be on screen. Its rim is a second shape behind
        // it, not a stroke round it.
        .background(Capsule().fill(Color(red: 0.07, green: 0.075, blue: 0.10)).padding(1.5))
        .background(Capsule().fill(Color.mint))
        .shadow(color: .black.opacity(0.3), radius: 7, y: 3)
    }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Name this timer")
                .font(.system(size: 11, weight: .semibold))
            artText("Running · rings at \(ArtSample.time(15, 45)), 14:52 left", .secondary, size: 9)
                .minimumScaleFactor(0.8)
                .padding(.top, 3)
            HStack(spacing: 1) {
                artText("Tea", size: 10.5)
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 1, height: 12)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(height: 32, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor.opacity(0.7), lineWidth: 1.5))
            .padding(.top, 9)
            HStack(spacing: 6) {
                ArtButton(title: "Discard Timer", isDestructive: true, fills: true)
                ArtButton(title: "Save Name", isProminent: true, fills: true)
            }
            .padding(.top, 10)
        }
        .padding(12)
        .artCard()
    }
}

/// The line a drag draws, as it is when it has caught on a round length: the
/// ruler's ticks along it, and the ring where the pointer is.
private struct ArtPullLine: View {
    let start: CGPoint
    let end: CGPoint
    let size: CGSize

    /// 15 minutes is the fifteenth step of the ruler, and the first and the
    /// fifth are round lengths too.
    private static let steps = 15
    private static let roundSteps: Set<Int> = [0, 4, 14]
    private static let color = Color.mint

    private var length: CGFloat { hypot(end.x - start.x, end.y - start.y) }
    private var along: CGVector {
        CGVector(dx: (end.x - start.x) / length, dy: (end.y - start.y) / length)
    }

    var body: some View {
        line.stroke(Self.color.opacity(0.26), style: StrokeStyle(lineWidth: 13, lineCap: .round))
        line.stroke(
            LinearGradient(
                colors: [Self.color.opacity(0.35), Self.color],
                startPoint: UnitPoint(x: start.x / size.width, y: start.y / size.height),
                endPoint: UnitPoint(x: end.x / size.width, y: end.y / size.height)
            ),
            style: StrokeStyle(lineWidth: 4, lineCap: .round)
        )
        ticks.stroke(Self.color.opacity(0.85), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        Circle()
            .fill(Self.color.opacity(0.3))
            .overlay(Circle().stroke(Self.color, lineWidth: 2.5))
            .frame(width: 30, height: 30)
            .shadow(color: Self.color.opacity(0.65), radius: 8)
            .position(end)
        Circle()
            .fill(Color.white)
            .frame(width: 9, height: 9)
            .position(end)
    }

    private var line: Path {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
    }

    /// One tick a step, taller at a round length, and none under the ring.
    private var ticks: Path {
        let lead: CGFloat = 12
        let spacing = (length - lead) / CGFloat(Self.steps - 1)
        return Path { path in
            for step in 0..<Self.steps {
                let distance = lead + CGFloat(step) * spacing
                guard distance < length - 24 else { break }
                let half: CGFloat = Self.roundSteps.contains(step) ? 7 : 3.5
                let x = start.x + along.dx * distance
                let y = start.y + along.dy * distance
                path.move(to: CGPoint(x: x - along.dy * half, y: y + along.dx * half))
                path.addLine(to: CGPoint(x: x + along.dy * half, y: y - along.dx * half))
            }
        }
    }
}

/// The top of the panel: the Quick start buttons, a length being typed, and
/// the routines.
private struct QuickStartArt: View {
    let size: CGSize

    private static let panelWidth: CGFloat = 348

    var body: some View {
        ArtMenuBar()
        ArtStatusItem()
            .position(x: size.width / 2, y: ArtMenuBar.height / 2)
        GuideBadge(number: 1)
            .position(x: size.width / 2 + 20, y: ArtMenuBar.height / 2 + 4)
        ArtPanel(arrowX: Self.panelWidth / 2) {
            VStack(alignment: .leading, spacing: 0) {
                artCaption("Quick start")
                ArtPresetGrid()
                    .guideBadge(2)
                    .padding(.top, 5)
                typedLength
                    .padding(.top, 7)
                artCaption("Routines")
                    .padding(.top, 10)
                HStack(spacing: 7) {
                    routine("Pomodoro", timers: 4)
                    routine("Morning", timers: 3)
                        .guideBadge(4)
                }
                .padding(.top, 5)
            }
            .padding(.horizontal, 16)
            .padding(.top, 11)
        }
        // Taller than the room there is for it: the picture stops, and the
        // panel goes on down to the timers.
        .frame(width: Self.panelWidth, height: 220)
        .offset(x: (size.width - Self.panelWidth) / 2, y: ArtMenuBar.height + 1)
    }

    private var typedLength: some View {
        HStack(spacing: 6) {
            HStack(spacing: 1) {
                Text("@3:30pm")
                    .font(.system(size: 10))
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 1, height: 11)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 19)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor.opacity(0.7), lineWidth: 1.5))
            ArtButton(title: "Ring at \(ArtSample.time(15, 30))")
                .guideBadge(3)
        }
    }

    private func routine(_ name: String, timers: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Text("\(timers) timers")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Image(systemName: "play.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(width: 140, height: 30)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.1)))
    }
}

/// The rest of the panel: two timers, the offer to undo, and the foot.
private struct RunningArt: View {
    private static let panelWidth: CGFloat = 352
    private static let panelLeft: CGFloat = 62
    /// How much of the panel is above the top of the picture: the Quick
    /// start buttons are up there.
    private static let hidden: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            ArtTimerRow(name: "Tea", detail: "3:42", identity: ArtSample.tea, progress: 0.55) {
                ArtSymbolButton(symbol: "checkmark")
                    .guideBadge(1, at: .top, outset: 13)
                ArtSymbolButton(symbol: "pause.fill")
                    .guideBadge(2, at: .top, outset: 13)
                ArtSymbolButton(symbol: "ellipsis")
            }
            .frame(height: 48)
            Divider().padding(.leading, 14)
            ArtTimerRow(
                name: "Stand-up", detail: "Paused · 12:00", identity: ArtSample.standUp,
                progress: 0.2, isPaused: true
            ) {
                ArtSymbolButton(symbol: "trash", color: .red)
                ArtSymbolButton(symbol: "arrow.counterclockwise")
                ArtSymbolButton(symbol: "play.fill")
                ArtSymbolButton(symbol: "ellipsis")
            }
            .frame(height: 48)
            Divider()
            undo
                .frame(height: 32)
            Divider()
            foot
                .frame(height: 34)
        }
        .padding(.top, Self.hidden + 2)
        .frame(width: Self.panelWidth, height: 184, alignment: .top)
        .artCard()
        .offset(x: Self.panelLeft, y: -Self.hidden)

        // What ⋯ on the first row opens, beside the button it opens from.
        ArtMenu(
            items: [
                "Pin to menu bar", nil, "Edit timer", "Reset timer", nil,
                "Add 1 min", "Subtract 1 min", nil, "Cancel timer",
            ],
            highlighted: "Edit timer"
        )
        .frame(width: 132)
        .guideBadge(3)
        .offset(x: Self.panelLeft + Self.panelWidth - 6, y: 26)
    }

    private var undo: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            artText("Cancelled Laundry")
            Spacer(minLength: 4)
            ArtButton(title: "Undo")
                .guideBadge(4, at: .leading, outset: 22)
        }
        .padding(.horizontal, 14)
    }

    private var foot: some View {
        HStack(spacing: 7) {
            Text("Stop all")
                .font(.system(size: 10))
                .foregroundStyle(.red)
            artText("1 running, 1 paused", .secondary)
            Spacer(minLength: 4)
            ArtSymbolButton(symbol: "clock.arrow.circlepath")
            ArtSymbolButton(symbol: "slider.horizontal.3")
            ArtSymbolButton(symbol: "ellipsis.circle")
        }
        .padding(.horizontal, 14)
    }
}

/// A timer that has ended: the clock in the menu bar, the card in the panel,
/// and the notification.
private struct FinishedArt: View {
    let size: CGSize

    private static let panelWidth: CGFloat = 336

    private var clockX: CGFloat { size.width * 0.37 }

    var body: some View {
        ArtMenuBar()
        ArtStatusItem(
            clock: ArtClock(face: .exclamation, color: .red, isFilled: true),
            text: "+2:15",
            textColor: .red
        )
        .position(x: clockX, y: ArtMenuBar.height / 2)
        GuideBadge(number: 1)
            .position(x: clockX - 20, y: ArtMenuBar.height / 2 + 4)
        ArtPanel(arrowX: Self.panelWidth / 2) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    artCaption("Quick start")
                    ArtPresetGrid(rows: 1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 11)
                .padding(.bottom, 10)
                card
            }
        }
        .frame(width: Self.panelWidth, height: 220)
        .offset(x: clockX - Self.panelWidth / 2, y: ArtMenuBar.height + 1)
        notification
            .frame(width: 176)
            .guideBadge(4)
            .offset(x: size.width - 176 - 18, y: ArtMenuBar.height + 12)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TimerIdentityBead(identity: ArtSample.tea, size: 22, urgent: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tea finished")
                        .font(.system(size: 11, weight: .semibold))
                    artText("2 min ago", .secondary, size: 9)
                }
                Spacer(minLength: 4)
                ArtSymbolButton(symbol: "speaker.slash.fill")
                    .guideBadge(3, at: .leading, outset: 15)
            }
            HStack(spacing: 6) {
                ArtButton(title: "Snooze 5 min")
                ArtButton(title: "Restart")
                ArtButton(title: "Mark done", isProminent: true)
                    .guideBadge(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
    }

    private var notification: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Timer finished")
                        .font(.system(size: 10, weight: .semibold))
                    artText("Tea", .secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            ForEach(["Snooze", "Mark done", "Restart"], id: \.self) { action in
                Divider()
                artText(action)
                    .frame(maxWidth: .infinity)
                    .frame(height: 17)
            }
        }
        .artCard(radius: 11)
    }
}

/// What the clock can show, and the menu a right-click on it opens.
private struct MenuBarArt: View {
    let size: CGSize

    private var clockX: CGFloat { size.width * 0.70 }

    var body: some View {
        ArtMenuBar()
        ArtStatusItem(
            clock: ArtClock(face: .symbol(ArtSample.tea.symbolName), color: ArtSample.tea.color.color),
            text: "3:42"
        )
        .position(x: clockX, y: ArtMenuBar.height / 2)
        GuideBadge(number: 1)
            .position(x: clockX - 20, y: ArtMenuBar.height / 2 + 4)
        ArtMenu(items: WelcomeArt.clockMenu)
            .frame(width: 142)
        .guideBadge(4)
        .offset(x: clockX - 12, y: ArtMenuBar.height + 4)
        HStack(alignment: .top, spacing: 10) {
            group("Preferences ▸ Menu bar") {
                specimen("Count", ArtStatusItem(text: "2"))
                specimen(
                    "Pinned",
                    ArtStatusItem(
                        clock: ArtClock(
                            face: .symbol(ArtSample.standUp.symbolName),
                            color: ArtSample.standUp.color.color
                        ),
                        text: "12:00"
                    )
                )
                specimen(
                    "Ring",
                    ArtStatusItem(
                        clock: ArtClock(
                            face: .symbol(ArtSample.tea.symbolName),
                            color: ArtSample.tea.color.color,
                            ring: 0.62
                        )
                    ),
                    isWide: false
                )
            }
            .guideBadge(2)
            group("In its last minute") {
                specimen(
                    "Deadline",
                    ArtStatusItem(
                        clock: ArtClock(face: .exclamation, color: .red),
                        text: "0:42",
                        textColor: .red
                    )
                )
            }
            .guideBadge(3)
        }
        .offset(x: 22, y: ArtMenuBar.height + 44)
    }

    private func group(_ title: String, @ViewBuilder _ specimens: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            artCaption(title)
            HStack(alignment: .top, spacing: 8) { specimens() }
        }
        .padding(10)
        .artCard()
    }

    /// The clock as one setting has it, on a length of menu bar, over the
    /// setting's name.
    private func specimen(_ name: String, _ item: ArtStatusItem, isWide: Bool = true) -> some View {
        VStack(spacing: 5) {
            item
                // The digits hang off the clock's right-hand side, so the
                // clock sits left of the middle to bring the pair to it.
                .offset(x: isWide ? -15 : 0)
                .frame(width: 74, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
            artText(name, .secondary, size: 9.5)
        }
    }
}

/// Preferences, open at Presets, and Timer History beside it.
private struct PreferencesArt: View {
    let size: CGSize

    var body: some View {
        ArtWindow(title: "Drag Timer Preferences") {
            HStack(spacing: 0) {
                panes
                    .frame(width: 102)
                Divider()
                presets
            }
        }
        .frame(width: 372, height: 152)
        .offset(x: 22, y: 16)
        ArtWindow(title: "Timer History") {
            history
        }
        .frame(width: 206, height: 128)
        .guideBadge(4)
        .offset(x: size.width - 206 - 20, y: 40)
    }

    /// The panes Preferences has, in its own order and under its own names.
    private var panes: some View {
        VStack(spacing: 1) {
            ForEach(SettingsPane.allCases) { entry in
                switch entry {
                case .general: pane(entry).guideBadge(2, at: .trailing, outset: -3)
                case .feel: pane(entry).guideBadge(3, at: .trailing, outset: -3)
                default: pane(entry)
                }
            }
        }
        .padding(6)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.04))
    }

    private func pane(_ entry: SettingsPane) -> some View {
        let isCurrent = entry == .presets
        return HStack(spacing: 5) {
            Image(systemName: entry.symbolName)
                .font(.system(size: 8.5))
                .foregroundStyle(isCurrent ? Color.white : Color.accentColor)
                .frame(width: 12)
            Text(entry.title)
                .font(.system(size: 10))
                .foregroundStyle(isCurrent ? Color.white : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .frame(height: 16)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isCurrent ? Color.accentColor : Color.clear)
        )
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Quick start presets")
                        .font(.system(size: 10.5, weight: .semibold))
                    artText("Drag rows to reorder. Up to 12 presets.", .secondary, size: 8.5)
                }
                Spacer(minLength: 4)
                ArtButton(title: "+ Add")
                    .guideBadge(1)
            }
            .padding(.bottom, 6)
            preset("Tea", "4 min · Glass, notification", ArtSample.tea)
            Divider()
            preset("Focus", "25 min · Hero, loops, notification", ArtSample.focus)
            Divider()
            preset("Laundry", "45 min · Ping, says name", ArtSample.laundry)
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
    }

    private func preset(_ name: String, _ detail: String, _ identity: TimerIdentity) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            TimerIdentityBead(identity: identity, size: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                artText(detail, .secondary, size: 8.5)
            }
            Spacer(minLength: 4)
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(height: 28)
    }

    private var history: some View {
        VStack(spacing: 0) {
            again("Tea", "4 min · Completed", ArtSample.tea)
            Divider()
            again("Focus", "25 min · Snoozed", ArtSample.focus)
            Divider()
            again("Laundry", "45 min · Cancelled", ArtSample.laundry)
            Spacer(minLength: 0)
            Divider()
            HStack(spacing: 4) {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 7.5))
                artText("Local on this Mac", .secondary, size: 8.5)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 20)
        }
    }

    private func again(_ name: String, _ detail: String, _ identity: TimerIdentity) -> some View {
        HStack(spacing: 8) {
            TimerIdentityBead(identity: identity, size: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                artText(detail, .secondary, size: 8.5)
            }
            Spacer(minLength: 4)
            ArtButton(title: "Again")
        }
        .padding(.horizontal, 10)
        .frame(height: 29)
    }
}
