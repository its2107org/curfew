import FamilyControls
import Foundation
import SwiftUI

/// The app's state: the plan, the chosen apps, and what's happening right now.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var snapshot: Snapshot
    var selection: FamilyActivitySelection
    private(set) var now = Date.now
    var screenTimeError: String?
    let sensor = BedroomSensor.shared

    var state: CurfewState { snapshot.state(at: now) }
    var plan: Plan { snapshot.plan }

    var hasFinishedSetup = UserDefaults.standard.bool(forKey: "finishedSetup") {
        didSet { UserDefaults.standard.set(hasFinishedSetup, forKey: "finishedSetup") }
    }

    private var ticker: Timer?

    private init() {
        Demo.prepareIfRequested()
        snapshot = SnapshotStore.load()
        selection = SnapshotStore.isDemo ? FamilyActivitySelection() : Blocker.loadSelection()
        sensor.onChange = { [weak self] in
            Task { @MainActor in self?.presenceChanged() }
        }
        if SnapshotStore.isDemo { hasFinishedSetup = !Demo.welcome }
        if BedroomSensor.wasStarted { sensor.start() }
        refreshPermission()
    }

    // MARK: - Lifecycle

    func appBecameActive() {
        refreshPermission()
        snapshot = SnapshotStore.load()
        Blocker.scheduleWakeUps(for: snapshot.plan)
        Blocker.evaluate()
        tick()
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in AppModel.shared.tick() }
        }
    }

    func appWentToBackground() {
        ticker?.invalidate()
        ticker = nil
        sensor.setLive(false)
    }

    func tick() {
        now = .now
        let fresh = SnapshotStore.load()
        if fresh != snapshot { snapshot = fresh }
    }

    private func presenceChanged() {
        Blocker.evaluate()
        tick()
    }

    // MARK: - Screen Time permission

    var canBlock: Bool { snapshot.canBlock }

    func refreshPermission() {
        let allowed = SnapshotStore.isDemo ? Demo.canBlock : Blocker.isAllowed
        if allowed != snapshot.canBlock {
            snapshot = SnapshotStore.update { $0.canBlock = allowed }
        }
    }

    func askForScreenTime() async {
        screenTimeError = nil
        guard !SnapshotStore.isDemo else { return }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            screenTimeError = "Apple hasn't allowed Curfew to lock apps yet. Everything else works, and locking switches on as soon as Apple says yes."
        }
        refreshPermission()
        Blocker.scheduleWakeUps(for: snapshot.plan)
        Blocker.evaluate()
        tick()
    }

    // MARK: - Changes

    func change(_ edit: (inout Plan) -> Void) {
        snapshot = SnapshotStore.update { edit(&$0.plan) }
        Blocker.scheduleWakeUps(for: snapshot.plan)
        Blocker.evaluate()
        tick()
    }

    func saveSelection(_ new: FamilyActivitySelection) {
        selection = new
        if SnapshotStore.isDemo { return }
        Blocker.saveSelection(new)
        Blocker.evaluate()
        tick()
    }

    func saveWindow(_ window: BedtimeWindow) {
        change { plan in
            if let index = plan.windows.firstIndex(where: { $0.id == window.id }) {
                plan.windows[index] = window
            } else {
                plan.windows.append(window)
            }
            plan.windows.sort { $0.start < $1.start }
        }
    }

    func deleteWindow(_ id: UUID) {
        change { $0.windows.removeAll { $0.id == id } }
    }

    func takeBreak() {
        Blocker.startBreak()
        tick()
    }

    func endBreak() {
        Blocker.endBreak()
        tick()
    }
}
