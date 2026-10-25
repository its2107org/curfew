import CoreBluetooth
import ServiceManagement
import SwiftUI

/// The Mac half of Curfew: a menu bar helper that gives off the Bluetooth signal the iPhone
/// listens for. It has no window; it lives in the menu bar and starts when the Mac does.
@main
struct CurfewMacApp: App {
    @State private var beacon = Beacon.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(beacon)
        } label: {
            Image(systemName: beacon.connectedPhones > 0 ? "moon.stars.fill" : "moon.stars")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuContent: View {
    @Environment(Beacon.self) private var beacon
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("keepAwake") private var keepAwake = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "moon.stars.fill")
                    .font(.title2)
                    .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.45))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Curfew").font(.headline)
                    Text(beacon.status).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Divider()

            Toggle("Open when the Mac starts", isOn: $opensAtLogin)
                .onChange(of: opensAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        opensAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Toggle("Keep the Mac awake for Curfew", isOn: $keepAwake)
                .onChange(of: keepAwake) { _, on in beacon.keepAwake(on) }
            Text("The screen can still sleep. If the Mac itself sleeps, Bluetooth stops and your iPhone won't know you're in the bedroom.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Button("Quit Curfew") { NSApplication.shared.terminate(nil) }
        }
        .toggleStyle(.switch)
        .padding(16)
        .frame(width: 300)
        .onAppear { opensAtLogin = SMAppService.mainApp.status == .enabled }
    }
}

@Observable
final class Beacon: NSObject, CBPeripheralManagerDelegate {
    static let shared = Beacon()

    private(set) var status = "Starting…"
    private(set) var connectedPhones = 0

    private var manager: CBPeripheralManager!
    private var heartbeat: CBMutableCharacteristic?
    private var subscribers: [CBCentral] = []
    private var timer: Timer?
    private var awake: NSObjectProtocol?

    private var name: String { Host.current().localizedName ?? "Mac" }

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: nil)
        // First run: start with the Mac, so Curfew survives restarts without anyone opening it.
        if !UserDefaults.standard.bool(forKey: "askedLogin") {
            UserDefaults.standard.set(true, forKey: "askedLogin")
            try? SMAppService.mainApp.register()
        }
        if UserDefaults.standard.object(forKey: "keepAwake") as? Bool ?? true { keepAwake(true) }
    }

    func keepAwake(_ on: Bool) {
        if on, awake == nil {
            awake = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: "Curfew gives off the bedroom signal for your iPhone")
        } else if !on, let awake {
            ProcessInfo.processInfo.endActivity(awake)
            self.awake = nil
        }
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            startService()
        case .poweredOff:
            status = "Bluetooth is off. Turn it on in System Settings."
        case .unauthorized:
            status = "Bluetooth isn't allowed. Allow Curfew in System Settings > Privacy & Security > Bluetooth."
        case .unsupported:
            status = "This Mac has no Bluetooth."
        default:
            status = "Waiting for Bluetooth…"
        }
    }

    private func startService() {
        manager.removeAllServices()
        let beat = CBMutableCharacteristic(type: Signal.heartbeat, properties: [.read, .notify], value: nil, permissions: [.readable])
        let service = CBMutableService(type: Signal.service, primary: true)
        service.characteristics = [beat]
        heartbeat = beat
        manager.add(service)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else {
            status = "Couldn't start: \(error!.localizedDescription)"
            return
        }
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Signal.service],
            CBAdvertisementDataLocalNameKey: Signal.localName
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            status = "Couldn't start: \(error.localizedDescription)"
            return
        }
        refreshStatus()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Signal.beatInterval, repeats: true) { [weak self] _ in self?.beat() }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        request.value = Data(name.utf8)
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if !subscribers.contains(where: { $0.identifier == central.identifier }) { subscribers.append(central) }
        refreshStatus()
        beat()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribers.removeAll { $0.identifier == central.identifier }
        refreshStatus()
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        beat()
    }

    /// Wakes each listening iPhone so it can measure the signal.
    private func beat() {
        guard let heartbeat, !subscribers.isEmpty else { return }
        manager.updateValue(Data(name.utf8), for: heartbeat, onSubscribedCentrals: nil)
    }

    private func refreshStatus() {
        connectedPhones = subscribers.count
        status = connectedPhones > 0 ? "Your iPhone is listening" : "On. Waiting for your iPhone."
    }
}
