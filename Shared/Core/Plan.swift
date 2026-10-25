import Foundation

/// A stretch of time when Curfew applies, such as 22:00 to 07:00 every night.
struct BedtimeWindow: Codable, Hashable, Identifiable {
    var id = UUID()
    /// Minutes after midnight.
    var start: Int
    var end: Int
    /// Days the window starts on, 1 = Sunday ... 7 = Saturday (as in `Calendar`).
    var days: Set<Int> = Set(1...7)
    var isOn = true

    static let standard = BedtimeWindow(start: 22 * 60, end: 7 * 60)

    var crossesMidnight: Bool { end <= start }

    /// Length in minutes (a window from 22:00 to 22:00 counts as a whole day).
    var length: Int { crossesMidnight ? end + 24 * 60 - start : end - start }

    /// Whether `date` falls inside this window.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isOn, !days.isEmpty else { return false }
        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let weekday = parts.weekday ?? 1
        if !crossesMidnight {
            return days.contains(weekday) && minute >= start && minute < end
        }
        if minute >= start { return days.contains(weekday) }
        // After midnight: it belongs to the window that started the day before.
        let yesterday = weekday == 1 ? 7 : weekday - 1
        return minute < end && days.contains(yesterday)
    }

    /// The next time this window starts or ends after `date`.
    func nextEdge(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isOn, !days.isEmpty else { return nil }
        let dayStart = calendar.startOfDay(for: date)
        var best: Date?
        for offset in -1...8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: dayStart) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard days.contains(weekday) else { continue }
            let begins = calendar.date(byAdding: .minute, value: start, to: day)!
            let ends = calendar.date(byAdding: .minute, value: start + length, to: day)!
            for edge in [begins, ends] where edge > date {
                if best == nil || edge < best! { best = edge }
            }
        }
        return best
    }

    var daysText: String {
        switch days {
        case Set(1...7): return "Every day"
        case Set(2...6): return "Weekdays"
        case [1, 7]: return "Weekends"
        case Set([1, 2, 3, 4, 5]): return "Sunday to Thursday nights"
        case Set([6, 7]): return "Friday and Saturday nights"
        default:
            let symbols = Calendar.current.shortWeekdaySymbols
            // Monday first, as in the UK.
            return [2, 3, 4, 5, 6, 7, 1].filter(days.contains).map { symbols[$0 - 1] }.joined(separator: ", ")
        }
    }

    var timesText: String { "\(Self.clock(start)) – \(Self.clock(end))" }

    static func clock(_ minutes: Int) -> String {
        var parts = DateComponents()
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        let date = Calendar.current.date(from: parts) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// How the chosen apps are used.
enum BlockStyle: String, Codable, CaseIterable {
    /// Lock just the chosen apps.
    case chosen
    /// Lock everything except the chosen apps.
    case allExceptChosen
}

/// Ian's set-up: what to lock and when.
struct Plan: Codable, Equatable {
    var isOn = true
    /// When true, the bedroom alone is enough: no times needed.
    var anyTime = false
    var windows: [BedtimeWindow] = [.standard]
    var style: BlockStyle = .chosen
    /// Shown in the app and the widget. The real choice lives in `Blocker`.
    var chosenCount = 0
    var chosenSummary = ""
    /// Signal strength (in dBm) that counts as "in the bedroom".
    var threshold = -72
    /// Seconds a locked break lasts.
    var breakLength: TimeInterval = 15 * 60

    func inSchedule(at date: Date) -> Bool {
        anyTime || windows.contains { $0.contains(date) }
    }

    /// When the schedule next starts or stops applying.
    func nextEdge(after date: Date) -> Date? {
        guard !anyTime else { return nil }
        return windows.compactMap { $0.nextEdge(after: date) }.min()
    }

    /// The next time the schedule switches on (skipping edges where it stays on).
    func nextStart(after date: Date) -> Date? {
        var cursor = date
        for _ in 0..<40 {
            guard let edge = nextEdge(after: cursor) else { return nil }
            if !inSchedule(at: edge.addingTimeInterval(-1)) && inSchedule(at: edge.addingTimeInterval(1)) { return edge }
            cursor = edge
        }
        return nil
    }

    /// The next time the schedule switches off.
    func nextEnd(after date: Date) -> Date? {
        var cursor = date
        for _ in 0..<40 {
            guard let edge = nextEdge(after: cursor) else { return nil }
            if inSchedule(at: edge.addingTimeInterval(-1)) && !inSchedule(at: edge.addingTimeInterval(1)) { return edge }
            cursor = edge
        }
        return nil
    }
}

/// Whether the iPhone is near the Mac, as last measured.
struct Presence: Codable, Equatable {
    var inBedroom = false
    /// When the iPhone last heard from the Mac.
    var lastHeard: Date?
    /// Latest smoothed signal strength.
    var strength: Int?
    var macName: String?

    /// A reading older than this is treated as "not in the bedroom". The Mac beats every 15
    /// seconds, so going quiet for this long means the link was lost without a goodbye.
    static let staleAfter: TimeInterval = 10 * 60

    func isInBedroom(at date: Date) -> Bool {
        guard inBedroom, let lastHeard else { return false }
        return date.timeIntervalSince(lastHeard) < Self.staleAfter
    }
}

/// What Curfew is doing right now.
enum CurfewState: Equatable {
    case off
    case locked(until: Date?)
    case onBreak(until: Date)
    /// In the bedroom, but outside the set times.
    case inBedroomFree(locksAt: Date?)
    /// Inside the set times, but not in the bedroom.
    case away(untilEnd: Date?)
    /// Neither.
    case idle(nextStart: Date?)

    var isLocked: Bool { if case .locked = self { true } else { false } }
}

/// Everything shared between the app, the monitor and the widget.
struct Snapshot: Codable, Equatable {
    var plan = Plan()
    var presence = Presence()
    var breakUntil: Date?
    /// Whether Apple has allowed Curfew to lock apps on this iPhone.
    var canBlock = false

    func state(at date: Date = .now) -> CurfewState {
        guard plan.isOn else { return .off }
        let scheduled = plan.inSchedule(at: date)
        let here = presence.isInBedroom(at: date)
        if scheduled && here {
            if let breakUntil, breakUntil > date { return .onBreak(until: breakUntil) }
            return .locked(until: plan.anyTime ? nil : plan.nextEnd(after: date))
        }
        if here { return .inBedroomFree(locksAt: plan.nextStart(after: date)) }
        if scheduled { return .away(untilEnd: plan.anyTime ? nil : plan.nextEnd(after: date)) }
        return .idle(nextStart: plan.anyTime ? nil : plan.nextStart(after: date))
    }
}

/// Keeps the snapshot in the shared keychain.
enum SnapshotStore {
    private static let service = "curfew"
    private static let account = "snapshot"

    static func load() -> Snapshot {
        if isDemo { return demoSnapshot }
        guard let data = SharedVault.read(service: service, account: account),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return Snapshot() }
        return snapshot
    }

    static func save(_ snapshot: Snapshot) {
        if isDemo { demoSnapshot = snapshot; return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        SharedVault.write(data, service: service, account: account)
    }

    @discardableResult
    static func update(_ change: (inout Snapshot) -> Void) -> Snapshot {
        var snapshot = load()
        change(&snapshot)
        save(snapshot)
        return snapshot
    }

    /// Demo mode (screenshots and self-checks) keeps everything in memory, so nothing real is touched.
    nonisolated(unsafe) static var isDemo = false
    nonisolated(unsafe) static var demoSnapshot = Snapshot()
}
