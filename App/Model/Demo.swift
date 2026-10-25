import Foundation

/// Launch options used by the automatic checks to take screenshots with made-up data:
/// -CurfewDemo (plus -CurfewDemoAway, -CurfewDemoFree, -CurfewDemoBreak, -CurfewDemoOff,
/// -CurfewDemoWaiting, -CurfewDemoWelcome, -CurfewDemoWindow, -CurfewDemoRange) and -CurfewSelfTest.
enum Demo {
    private static let arguments = ProcessInfo.processInfo.arguments
    static func has(_ flag: String) -> Bool { arguments.contains("-CurfewDemo\(flag)") }

    static var isOn: Bool { arguments.contains("-CurfewDemo") || arguments.contains("-CurfewSelfTest") }
    static var welcome: Bool { has("Welcome") }
    static var canBlock: Bool { !has("Waiting") }
    static var openWindow: Bool { has("Window") }
    static var openRange: Bool { has("Range") }

    static func prepareIfRequested() {
        guard isOn, !SnapshotStore.isDemo else { return }
        SnapshotStore.isDemo = true
        var snapshot = Snapshot()
        snapshot.canBlock = canBlock
        snapshot.plan.windows = [
            BedtimeWindow(start: 22 * 60 + 30, end: 7 * 60, days: [1, 2, 3, 4, 5]),
            BedtimeWindow(start: 23 * 60 + 30, end: 8 * 60 + 30, days: [6, 7])
        ]
        snapshot.plan.chosenCount = 9
        snapshot.plan.chosenSummary = "7 apps, 2 categories"
        snapshot.presence = Presence(inBedroom: !has("Away") && !has("Waiting"), lastHeard: .now, strength: -58, macName: "Mac mini")
        if has("Off") { snapshot.plan.isOn = false }
        if has("Free") {
            // Shown as if it were the early evening: in the bedroom, but before bedtime.
            snapshot.plan.windows = [BedtimeWindow(start: (Calendar.current.component(.hour, from: .now) + 2) % 24 * 60, end: 7 * 60)]
        } else {
            // Make "now" inside a window so the locked screen shows.
            let minute = Calendar.current.component(.hour, from: .now) * 60 + Calendar.current.component(.minute, from: .now)
            snapshot.plan.windows[0].start = (minute + 24 * 60 - 60) % (24 * 60)
            snapshot.plan.windows[0].end = (minute + 7 * 60) % (24 * 60)
            snapshot.plan.windows[0].days = Set(1...7)
        }
        if has("Break") { snapshot.breakUntil = .now.addingTimeInterval(12 * 60) }
        SnapshotStore.demoSnapshot = snapshot
    }
}
