import AppKit
import SwiftUI

final class HistoryWindowController: NSWindowController {
    init(timerEngine: TimerEngine) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Timer History"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 500, height: 400)
        window.setFrameAutosaveName("DragTimer.History")
        window.contentViewController = NSHostingController(rootView: HistoryView(timerEngine: timerEngine))
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }
}

private enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case completed = "Completed"
    case cancelled = "Cancelled"
    case snoozed = "Snoozed"
    var id: String { rawValue }
}

private struct HistoryView: View {
    @ObservedObject var timerEngine: TimerEngine
    @State private var filter: HistoryFilter = .all
    @State private var confirmsClear = false

    private var recentEntries: [TimerHistoryEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        return timerEngine.historyEntries.filter { entry in
            guard entry.endedAt >= cutoff else { return false }
            switch filter {
            case .all: return entry.outcome != .discarded
            case .completed: return entry.outcome == .completed
            case .cancelled: return entry.outcome == .cancelled
            case .snoozed: return entry.resolution == .snoozed
            }
        }
    }

    private var insights: TimerHistoryInsights {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        return TimerHistoryInsights.calculate(entries: timerEngine.historyEntries, since: cutoff)
    }

    var body: some View {
        VStack(spacing: 0) {
            summary
            Divider()
            Picker("Filter", selection: $filter) {
                ForEach(HistoryFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            if recentEntries.isEmpty {
                ContentUnavailableView(
                    "No timer history",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Finished and cancelled timers will appear here. They stay on this Mac.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groupedEntries, id: \.date) { group in
                        Section(dayLabel(group.date)) {
                            ForEach(group.entries) { entry in
                                HistoryRow(entry: entry) {
                                    timerEngine.restartHistoryEntry(id: entry.id)
                                }
                            }
                        }
                    }
                }
            }

            Divider()
            HStack {
                Button("Clear history…", role: .destructive) { confirmsClear = true }
                    .disabled(timerEngine.historyEntries.isEmpty)
                Spacer()
                Label("Local on this Mac", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .confirmationDialog("Clear all timer history?", isPresented: $confirmsClear) {
            Button("Clear history", role: .destructive) { timerEngine.clearHistory() }
        } message: {
            Text("Active timers and presets will not be changed.")
        }
    }

    private var groupedEntries: [(date: Date, entries: [TimerHistoryEntry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: recentEntries) { calendar.startOfDay(for: $0.endedAt) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private var summary: some View {
        HStack(spacing: 22) {
            insight("Completed", value: String(insights.completedCount))
            insight("Cancelled", value: String(insights.cancelledCount))
            insight("Snoozed", value: String(insights.snoozedCount))
            insight(
                "Average plan",
                value: insights.averagePlannedDuration.map { DurationText.compact($0) } ?? "—"
            )
            Spacer()
        }
        .padding()
    }

    private func insight(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title3, design: .monospaced).weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct HistoryRow: View {
    let entry: TimerHistoryEntry
    let onAgain: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TimerIdentityBead(identity: entry.identity, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.label).fontWeight(.medium).lineLimit(1)
                Text("\(DurationText.compact(entry.plannedDuration)) · \(outcomeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.endedAt, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("Again", action: onAgain)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private var outcomeText: String {
        if let resolution = entry.resolution {
            switch resolution {
            case .markDone: return "Completed"
            case .snoozed: return "Snoozed"
            case .restarted: return "Restarted"
            }
        }
        return entry.outcome.rawValue.capitalized
    }
}
