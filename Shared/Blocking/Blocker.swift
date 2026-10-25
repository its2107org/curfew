import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import WidgetKit

/// Locks and unlocks the chosen apps using Screen Time.
///
/// Both the app (when the iPhone comes and goes from the bedroom) and the monitor extension
/// (when a bedtime window starts or ends) call `evaluate`, which works out what should happen
/// from the shared snapshot and applies it. Running it twice is harmless.
enum Blocker {
    private static let store = ManagedSettingsStore(named: .init("curfew"))
    private static let service = "curfew"
    private static let selectionAccount = "selection"

    // MARK: - The chosen apps

    static func loadSelection() -> FamilyActivitySelection {
        guard let data = SharedVault.read(service: service, account: selectionAccount),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection(includeEntireCategory: true)
        }
        return selection
    }

    static func saveSelection(_ selection: FamilyActivitySelection) {
        if let data = try? JSONEncoder().encode(selection) {
            SharedVault.write(data, service: service, account: selectionAccount)
        }
        SnapshotStore.update {
            $0.plan.chosenCount = selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
            $0.plan.chosenSummary = summary(of: selection)
        }
    }

    static func summary(of selection: FamilyActivitySelection) -> String {
        var parts: [String] = []
        let apps = selection.applicationTokens.count
        let categories = selection.categoryTokens.count
        let sites = selection.webDomainTokens.count
        if apps > 0 { parts.append(apps == 1 ? "1 app" : "\(apps) apps") }
        if categories > 0 { parts.append(categories == 1 ? "1 category" : "\(categories) categories") }
        if sites > 0 { parts.append(sites == 1 ? "1 website" : "\(sites) websites") }
        return parts.isEmpty ? "Nothing chosen yet" : parts.joined(separator: ", ")
    }

    // MARK: - Locking

    static var isAllowed: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    /// Works out whether the apps should be locked right now, and makes it so.
    /// `lookAhead` nudges the clock forward a little when called exactly at a window's edge.
    @discardableResult
    static func evaluate(lookAhead: TimeInterval = 0) -> CurfewState {
        let snapshot = SnapshotStore.load()
        let state = snapshot.state(at: .now.addingTimeInterval(lookAhead))
        if !SnapshotStore.isDemo {
            if state.isLocked && isAllowed {
                lock(snapshot.plan.style, selection: loadSelection())
            } else {
                store.clearAllSettings()
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        return state
    }

    private static func lock(_ style: BlockStyle, selection: FamilyActivitySelection) {
        switch style {
        case .chosen:
            store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
            store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
            store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
            store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        case .allExceptChosen:
            store.shield.applications = nil
            store.shield.applicationCategories = .all(except: selection.applicationTokens)
            store.shield.webDomains = nil
            store.shield.webDomainCategories = .all(except: selection.webDomainTokens)
        }
    }

    // MARK: - Wake-ups at the start and end of each window

    private static let windowPrefix = "window-"
    static let breakActivity = DeviceActivityName("break")

    /// Asks Screen Time to wake the monitor at the start and end of every window.
    /// Days are checked when it wakes, so each window needs just one daily wake-up.
    static func scheduleWakeUps(for plan: Plan) {
        guard isAllowed, !SnapshotStore.isDemo else { return }
        let center = DeviceActivityCenter()
        center.stopMonitoring(center.activities.filter { $0.rawValue.hasPrefix(windowPrefix) })
        guard plan.isOn, !plan.anyTime else { return }
        // Screen Time allows a limited number of schedules; the same times only need one.
        var seen = Set<[Int]>()
        for window in plan.windows where window.isOn && !window.days.isEmpty && window.length >= 15 {
            guard seen.insert([window.start, window.end]).inserted else { continue }
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: window.start / 60, minute: window.start % 60),
                intervalEnd: DateComponents(hour: window.end / 60, minute: window.end % 60),
                repeats: true
            )
            try? center.startMonitoring(DeviceActivityName("\(windowPrefix)\(window.start)-\(window.end)"), during: schedule)
        }
    }

    /// Unlocks for a short break and asks Screen Time to wake the monitor when it's over.
    static func startBreak() {
        let snapshot = SnapshotStore.update { $0.breakUntil = .now.addingTimeInterval($0.plan.breakLength) }
        evaluate()
        guard isAllowed, !SnapshotStore.isDemo, let until = snapshot.breakUntil else { return }
        let center = DeviceActivityCenter()
        center.stopMonitoring([breakActivity])
        let calendar = Calendar.current
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        // Screen Time won't schedule anything shorter than 15 minutes, so the wake-up runs a minute past the break.
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(fields, from: .now),
            intervalEnd: calendar.dateComponents(fields, from: until.addingTimeInterval(60)),
            repeats: false
        )
        try? center.startMonitoring(breakActivity, during: schedule)
    }

    static func endBreak() {
        SnapshotStore.update { $0.breakUntil = nil }
        if !SnapshotStore.isDemo { DeviceActivityCenter().stopMonitoring([breakActivity]) }
        evaluate()
    }
}
