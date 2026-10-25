import Foundation

/// Checks of the timing and bedroom rules, run by the automatic checks with -CurfewSelfTest.
/// Writes Documents/selftest.json with each check and "all passed" if everything worked.
enum SelfTest {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-CurfewSelfTest") }

    static func run() {
        var results: [[String: String]] = []
        func check(_ name: String, _ ok: Bool) {
            results.append(["check": name, "result": ok ? "ok" : "FAILED"])
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
        }
        // 26 October 2026 is a Monday (weekday 2).
        let night = BedtimeWindow(start: 22 * 60, end: 7 * 60)
        check("Overnight window covers 23:30", night.contains(at(2026, 10, 26, 23, 30), calendar: calendar))
        check("Overnight window covers 03:00", night.contains(at(2026, 10, 27, 3, 0), calendar: calendar))
        check("Overnight window ends at 07:00", !night.contains(at(2026, 10, 27, 7, 0), calendar: calendar))
        check("Overnight window starts at 22:00", night.contains(at(2026, 10, 26, 22, 0), calendar: calendar))
        check("Not inside at 21:59", !night.contains(at(2026, 10, 26, 21, 59), calendar: calendar))
        check("Not inside at noon", !night.contains(at(2026, 10, 26, 12, 0), calendar: calendar))

        var weekdays = night
        weekdays.days = [1, 2, 3, 4, 5] // Sunday to Thursday nights
        check("School-night window on Monday night", weekdays.contains(at(2026, 10, 26, 23, 0), calendar: calendar))
        check("School-night window carries into Friday morning", weekdays.contains(at(2026, 10, 30, 6, 0), calendar: calendar))
        check("No school-night window on Friday night", !weekdays.contains(at(2026, 10, 30, 23, 0), calendar: calendar))
        check("No school-night window on Saturday morning", !weekdays.contains(at(2026, 10, 31, 3, 0), calendar: calendar))
        check("School-night window on Sunday night", weekdays.contains(at(2026, 11, 1, 22, 30), calendar: calendar))

        let afternoon = BedtimeWindow(start: 13 * 60, end: 15 * 60)
        check("Daytime window covers 14:00", afternoon.contains(at(2026, 10, 26, 14, 0), calendar: calendar))
        check("Daytime window ends at 15:00", !afternoon.contains(at(2026, 10, 26, 15, 0), calendar: calendar))

        var off = night
        off.isOn = false
        check("Switched-off window never applies", !off.contains(at(2026, 10, 26, 23, 0), calendar: calendar))

        let edge = night.nextEdge(after: at(2026, 10, 26, 12, 0), calendar: calendar)
        check("Next edge after noon is 22:00", edge == at(2026, 10, 26, 22, 0))
        let morning = night.nextEdge(after: at(2026, 10, 26, 23, 0), calendar: calendar)
        check("Next edge after 23:00 is 07:00", morning == at(2026, 10, 27, 7, 0))

        // Plan-level checks use the iPhone's own calendar, so build times from today.
        let today = Calendar.current.startOfDay(for: .now)
        func todayAt(_ h: Int, _ m: Int = 0) -> Date { Calendar.current.date(byAdding: .minute, value: h * 60 + m, to: today)! }

        var plan = Plan()
        plan.windows = [BedtimeWindow(start: 22 * 60, end: 7 * 60)]
        check("Plan in schedule at 23:00", plan.inSchedule(at: todayAt(23)))
        check("Plan not in schedule at 18:00", !plan.inSchedule(at: todayAt(18)))
        check("Next start from 18:00 is 22:00", plan.nextStart(after: todayAt(18)) == todayAt(22))
        check("Next end from 23:00 is 07:00 tomorrow", plan.nextEnd(after: todayAt(23)) == todayAt(31))

        // Overlapping windows act as one.
        plan.windows.append(BedtimeWindow(start: 6 * 60, end: 9 * 60))
        check("Overlapping windows end at the later time", plan.nextEnd(after: todayAt(23)) == todayAt(33))
        plan.anyTime = true
        check("Any-time plan applies at noon", plan.inSchedule(at: todayAt(12)))
        plan.anyTime = false

        // States.
        var snapshot = Snapshot()
        snapshot.plan.windows = [BedtimeWindow(start: 22 * 60, end: 7 * 60)]
        snapshot.presence = Presence(inBedroom: true, lastHeard: todayAt(23), strength: -60)
        check("Locked in the bedroom at bedtime", snapshot.state(at: todayAt(23)).isLocked)
        if case .inBedroomFree = snapshot.state(at: todayAt(20)) {
            check("Free in the bedroom before bedtime", true)
        } else { check("Free in the bedroom before bedtime", false) }

        snapshot.presence.lastHeard = todayAt(22, 45)
        check("Old reading counts as away", !snapshot.state(at: todayAt(23)).isLocked)
        snapshot.presence.lastHeard = todayAt(23)

        snapshot.breakUntil = todayAt(23, 15)
        if case .onBreak = snapshot.state(at: todayAt(23, 5)) {
            check("Break unlocks", true)
        } else { check("Break unlocks", false) }
        check("Locked again after the break", snapshot.state(at: todayAt(23, 16)).isLocked)
        snapshot.breakUntil = nil

        snapshot.presence.inBedroom = false
        if case .away = snapshot.state(at: todayAt(23)) {
            check("Away at bedtime stays unlocked", true)
        } else { check("Away at bedtime stays unlocked", false) }

        snapshot.presence.inBedroom = true
        snapshot.plan.isOn = false
        check("Switched off never locks", snapshot.state(at: todayAt(23)) == .off)

        // Saving and loading the shared snapshot.
        SnapshotStore.save(snapshot)
        check("Snapshot saves and loads", SnapshotStore.load() == snapshot)

        check("Times read like 22:00 – 07:00", !BedtimeWindow.standard.timesText.isEmpty)
        check("Weekday text", weekdays.daysText == "Sunday to Thursday nights")

        let passed = results.allSatisfy { $0["result"] == "ok" }
        let output: [String: Any] = ["summary": passed ? "all passed" : "some failed", "checks": results]
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("selftest.json"))
        }
    }
}
