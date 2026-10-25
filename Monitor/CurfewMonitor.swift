import DeviceActivity
import Foundation

/// Screen Time wakes this up at the start and end of each bedtime window (and at the end of a
/// break), even when the Curfew app isn't running. It locks or unlocks the apps if needed.
final class CurfewMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // Look a little ahead, in case the wake-up arrives a moment before the window opens.
        Blocker.evaluate(lookAhead: 30)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity == Blocker.breakActivity {
            SnapshotStore.update { snapshot in
                if let until = snapshot.breakUntil, until <= .now.addingTimeInterval(30) { snapshot.breakUntil = nil }
            }
        }
        Blocker.evaluate(lookAhead: 30)
    }
}
