import Combine
import Foundation

enum MenuBarDisplayMode: String, Codable, CaseIterable, Identifiable {
    case deadline
    case count
    case pinned
    case ring

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deadline: return "Deadline"
        case .count: return "Count"
        case .pinned: return "Pinned"
        case .ring: return "Ring"
        }
    }
}

enum CountdownScale: String, Codable, CaseIterable, Identifiable {
    case standard
    case large
    case extraLarge

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .standard: return "Default"
        case .large: return "Large"
        case .extraLarge: return "Extra large"
        }
    }
    var factor: Double {
        switch self {
        case .standard: return 1
        case .large: return 1.15
        case .extraLarge: return 1.3
        }
    }
}

enum ContrastMode: String, Codable, CaseIterable, Identifiable {
    case system
    case alwaysOn

    var id: String { rawValue }
    var displayName: String { self == .system ? "Follow system" : "Always on" }
}

enum UrgentThreshold: Int, Codable, CaseIterable, Identifiable {
    case off = 0
    case oneMinute = 60
    case threeMinutes = 180
    case fiveMinutes = 300
    case tenMinutes = 600

    var id: Int { rawValue }
    var displayName: String {
        switch self {
        case .off: return "Off"
        case .oneMinute: return "1 minute"
        case .threeMinutes: return "3 minutes"
        case .fiveMinutes: return "5 minutes"
        case .tenMinutes: return "10 minutes"
        }
    }
}

final class AppSettings: ObservableObject {
    /// All fields remain optional in storage so adding a setting never makes an
    /// existing settings blob undecodable. Runtime properties are normalized.
    private struct StoredSettings: Codable {
        var version: Int?
        var preset: FeelPreset?
        var physics: DragPhysicsSettings?
        var hapticsEnabled: Bool?
        var snapDuringDrag: Bool?
        var defaultSoundName: String?
        var defaultVolume: Double?
        var defaultLoop: Bool?
        var defaultNotificationsEnabled: Bool?
        var defaultLabel: String?
        var defaultSnoozeMinutes: Int?
        var quickStartMinutes: [Int]?
        var quickStartPresets: [QuickStartPreset]?
        var askForLabelAfterDrag: Bool?
        var firePastDueOnWake: Bool?
        var menuBarDisplayMode: MenuBarDisplayMode?
        var pinnedTimerID: UUID?
        var showZeroCount: Bool?
        var countdownScale: CountdownScale?
        var contrastMode: ContrastMode?
        var urgentThreshold: UrgentThreshold?
        var automaticallyChecksForUpdates: Bool?
        var lastUpdateCheckAt: Date?
        var cachedUpdateTag: String?
        var cachedUpdateURLString: String?
        var dismissedReleaseTag: String?
    }

    private let defaults: UserDefaults
    private let storageKey = "DragTimer.AppSettings.v1"

    @Published var preset: FeelPreset { didSet { persist() } }
    @Published var physics: DragPhysicsSettings { didSet { persist() } }
    @Published var hapticsEnabled: Bool { didSet { persist() } }
    @Published var snapDuringDrag: Bool { didSet { persist() } }
    @Published var defaultSoundName: String { didSet { persist() } }
    @Published var defaultVolume: Double { didSet { persist() } }
    @Published var defaultLoop: Bool { didSet { persist() } }
    @Published var defaultNotificationsEnabled: Bool { didSet { persist() } }
    @Published var defaultLabel: String { didSet { persist() } }
    @Published var defaultSnoozeMinutes: Int { didSet { persist() } }
    @Published private(set) var quickStartPresets: [QuickStartPreset]
    @Published var askForLabelAfterDrag: Bool { didSet { persist() } }
    @Published var firePastDueOnWake: Bool { didSet { persist() } }
    @Published var menuBarDisplayMode: MenuBarDisplayMode { didSet { persist() } }
    @Published var pinnedTimerID: UUID? { didSet { persist() } }
    @Published var showZeroCount: Bool { didSet { persist() } }
    @Published var countdownScale: CountdownScale { didSet { persist() } }
    @Published var contrastMode: ContrastMode { didSet { persist() } }
    @Published var urgentThreshold: UrgentThreshold { didSet { persist() } }
    @Published var automaticallyChecksForUpdates: Bool { didSet { persist() } }
    @Published var lastUpdateCheckAt: Date? { didSet { persist() } }
    @Published var cachedUpdateTag: String? { didSet { persist() } }
    @Published var cachedUpdateURLString: String? { didSet { persist() } }
    @Published var dismissedReleaseTag: String? { didSet { persist() } }

    static let defaultQuickStartMinutes = [5, 10, 15, 30, 60, 120, 180, 240]
    static let maximumDragDurationHoursRange = 4...24
    static let maximumPresetCount = 12

    var quickStartMinutes: [Int] {
        quickStartPresets.map { Int(($0.duration / 60).rounded()) }
    }

    var maximumDragDurationHours: Int {
        let hours = Int((physics.maximumDuration / (60 * 60)).rounded())
        return min(
            max(hours, Self.maximumDragDurationHoursRange.lowerBound),
            Self.maximumDragDurationHoursRange.upperBound
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(StoredSettings.self, from: $0) }

        preset = stored?.preset ?? .snappy
        var restoredPhysics = (stored?.physics ?? .forPreset(.snappy)).sanitized
        if restoredPhysics.snapTolerance == 12 {
            restoredPhysics.snapTolerance = 24
        }
        physics = restoredPhysics
        hapticsEnabled = stored?.hapticsEnabled ?? true
        snapDuringDrag = stored?.snapDuringDrag ?? true
        defaultSoundName = AlertSound.normalizedName(stored?.defaultSoundName ?? AlertSound.glass.rawValue)
        defaultVolume = min(max(stored?.defaultVolume ?? 0.8, 0), 1)
        defaultLoop = stored?.defaultLoop ?? false
        defaultNotificationsEnabled = stored?.defaultNotificationsEnabled ?? true
        defaultLabel = stored?.defaultLabel ?? "Timer"
        defaultSnoozeMinutes = min(max(stored?.defaultSnoozeMinutes ?? 5, 1), 60)
        askForLabelAfterDrag = stored?.askForLabelAfterDrag ?? true
        firePastDueOnWake = stored?.firePastDueOnWake ?? true
        menuBarDisplayMode = stored?.menuBarDisplayMode ?? .deadline
        pinnedTimerID = stored?.pinnedTimerID
        showZeroCount = stored?.showZeroCount ?? false
        countdownScale = stored?.countdownScale ?? .standard
        contrastMode = stored?.contrastMode ?? .system
        urgentThreshold = stored?.urgentThreshold ?? .oneMinute
        automaticallyChecksForUpdates = stored?.automaticallyChecksForUpdates ?? true
        lastUpdateCheckAt = stored?.lastUpdateCheckAt
        cachedUpdateTag = stored?.cachedUpdateTag
        cachedUpdateURLString = stored?.cachedUpdateURLString
        dismissedReleaseTag = stored?.dismissedReleaseTag

        if let presets = stored?.quickStartPresets {
            quickStartPresets = Self.sanitizePresets(presets)
        } else {
            let legacyMinutes = stored?.quickStartMinutes ?? Self.defaultQuickStartMinutes
            let alert = PresetAlertOptions(
                soundName: AlertSound.normalizedName(stored?.defaultSoundName ?? AlertSound.glass.rawValue),
                volume: min(max(stored?.defaultVolume ?? 0.8, 0), 1),
                loop: stored?.defaultLoop ?? false,
                notify: stored?.defaultNotificationsEnabled ?? true,
                snoozeMinutes: min(max(stored?.defaultSnoozeMinutes ?? 5, 1), 60)
            )
            quickStartPresets = Self.presets(from: legacyMinutes, alert: alert)
        }

        // Persist once to make migrations stable across subsequent launches.
        persist()
    }

    func applyPreset(_ newPreset: FeelPreset) {
        guard newPreset != .custom else { return }
        preset = newPreset
        physics = .forPreset(newPreset, basedOn: physics)
    }

    func updatePhysics(_ update: (inout DragPhysicsSettings) -> Void) {
        var copy = physics
        update(&copy)
        physics = copy.sanitized
        if preset != .custom {
            preset = .custom
        }
    }

    func defaultOptions(label: String? = nil) -> TimerOptions {
        TimerOptions(
            label: label ?? defaultLabel,
            soundName: defaultSoundName,
            volume: defaultVolume,
            loop: defaultLoop,
            notify: defaultNotificationsEnabled,
            snoozeMinutes: defaultSnoozeMinutes,
            identity: .default
        )
    }

    func setQuickStartPresets(_ presets: [QuickStartPreset]) {
        quickStartPresets = Self.sanitizePresets(presets)
        persist()
    }

    /// Compatibility helper for callers and tests from the v1 preset UI.
    func setQuickStartMinutes(_ minutes: [Int]) {
        let alert = PresetAlertOptions(
            soundName: defaultSoundName,
            volume: defaultVolume,
            loop: defaultLoop,
            notify: defaultNotificationsEnabled,
            snoozeMinutes: defaultSnoozeMinutes
        )
        quickStartPresets = Self.presets(from: minutes, alert: alert)
        persist()
    }

    @discardableResult
    func addPreset(_ preset: QuickStartPreset) -> Bool {
        guard quickStartPresets.count < Self.maximumPresetCount else { return false }
        quickStartPresets.append(Self.sanitizePreset(preset))
        persist()
        return true
    }

    func updatePreset(_ preset: QuickStartPreset) {
        guard let index = quickStartPresets.firstIndex(where: { $0.id == preset.id }) else { return }
        quickStartPresets[index] = Self.sanitizePreset(preset)
        persist()
    }

    @discardableResult
    func duplicatePreset(id: UUID) -> Bool {
        guard quickStartPresets.count < Self.maximumPresetCount,
              let index = quickStartPresets.firstIndex(where: { $0.id == id }) else { return false }
        var copy = quickStartPresets[index]
        copy.id = UUID()
        if !copy.label.isEmpty { copy.label += " Copy" }
        quickStartPresets.insert(copy, at: index + 1)
        persist()
        return true
    }

    func removePreset(id: UUID) {
        quickStartPresets.removeAll { $0.id == id }
        persist()
    }

    func movePreset(id: UUID, offset: Int) {
        guard let source = quickStartPresets.firstIndex(where: { $0.id == id }) else { return }
        let destination = min(max(source + offset, 0), quickStartPresets.count - 1)
        guard source != destination else { return }
        let preset = quickStartPresets.remove(at: source)
        quickStartPresets.insert(preset, at: destination)
        persist()
    }

    func movePresets(fromOffsets: IndexSet, toOffset: Int) {
        var values = quickStartPresets
        let moving = fromOffsets.sorted().map { values[$0] }
        for index in fromOffsets.sorted(by: >) { values.remove(at: index) }
        let removedBeforeDestination = fromOffsets.filter { $0 < toOffset }.count
        let destination = min(max(toOffset - removedBeforeDestination, 0), values.count)
        values.insert(contentsOf: moving, at: destination)
        quickStartPresets = values
        persist()
    }

    func restoreDefaultPresets() {
        setQuickStartMinutes(Self.defaultQuickStartMinutes)
    }

    func setMaximumDragDurationHours(_ hours: Int) {
        let clampedHours = min(
            max(hours, Self.maximumDragDurationHoursRange.lowerBound),
            Self.maximumDragDurationHoursRange.upperBound
        )
        var copy = physics
        copy.maximumDuration = TimeInterval(clampedHours * 60 * 60)
        physics = copy.sanitized
    }

    private static func presets(from minutes: [Int], alert: PresetAlertOptions) -> [QuickStartPreset] {
        let normalized = minutes.prefix(maximumPresetCount).map { min(max($0, 1), 1_440) }
        let values = normalized.isEmpty ? defaultQuickStartMinutes : Array(normalized)
        return values.map {
            QuickStartPreset(duration: TimeInterval($0 * 60), alert: alert)
        }
    }

    private static func sanitizePresets(_ presets: [QuickStartPreset]) -> [QuickStartPreset] {
        let limited = presets.prefix(maximumPresetCount).map(sanitizePreset)
        return Array(limited)
    }

    private static func sanitizePreset(_ preset: QuickStartPreset) -> QuickStartPreset {
        QuickStartPreset(
            id: preset.id,
            duration: preset.duration,
            label: preset.label,
            alert: preset.alert,
            identity: preset.identity
        )
    }

    private func persist() {
        let stored = StoredSettings(
            version: 2,
            preset: preset,
            physics: physics,
            hapticsEnabled: hapticsEnabled,
            snapDuringDrag: snapDuringDrag,
            defaultSoundName: defaultSoundName,
            defaultVolume: defaultVolume,
            defaultLoop: defaultLoop,
            defaultNotificationsEnabled: defaultNotificationsEnabled,
            defaultLabel: defaultLabel,
            defaultSnoozeMinutes: defaultSnoozeMinutes,
            quickStartMinutes: nil,
            quickStartPresets: quickStartPresets,
            askForLabelAfterDrag: askForLabelAfterDrag,
            firePastDueOnWake: firePastDueOnWake,
            menuBarDisplayMode: menuBarDisplayMode,
            pinnedTimerID: pinnedTimerID,
            showZeroCount: showZeroCount,
            countdownScale: countdownScale,
            contrastMode: contrastMode,
            urgentThreshold: urgentThreshold,
            automaticallyChecksForUpdates: automaticallyChecksForUpdates,
            lastUpdateCheckAt: lastUpdateCheckAt,
            cachedUpdateTag: cachedUpdateTag,
            cachedUpdateURLString: cachedUpdateURLString,
            dismissedReleaseTag: dismissedReleaseTag
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
