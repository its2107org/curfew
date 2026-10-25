import CoreBluetooth
import Foundation

/// Listens for the Mac's Bluetooth signal and works out whether the iPhone is in the bedroom.
///
/// The iPhone stays connected to the Mac while it's in range. The Mac sends a heartbeat every
/// 15 seconds, which wakes Curfew in the background just long enough to measure the signal
/// strength. When the link drops (out of range) iOS wakes Curfew too, and it keeps a standing
/// request to reconnect plus a scan for the Mac's service, so it notices coming back.
@Observable
final class BedroomSensor: NSObject {
    static let shared = BedroomSensor()

    private(set) var bluetooth: CBManagerState = .unknown
    private(set) var isConnected = false
    /// Latest smoothed signal strength in dBm (about -40 right next to the Mac, -90 far away).
    private(set) var strength: Int?
    private(set) var macName: String?
    private(set) var isStarted = false

    /// Called when "in the bedroom" changes.
    var onChange: (() -> Void)?

    private var central: CBCentralManager?
    private var mac: CBPeripheral?
    private var samples: [Int] = []
    private var lastSaved = Date.distantPast
    private var liveTimer: Timer?

    private static let restoreID = "curfew.central"
    private static let knownKey = "knownMac"
    private static let startedKey = "sensorStarted"

    /// Whether Bluetooth was switched on in an earlier session (so it's safe to start at launch
    /// without showing the permission prompt out of the blue).
    static var wasStarted: Bool { UserDefaults.standard.bool(forKey: startedKey) }

    func start() {
        guard central == nil, !SnapshotStore.isDemo else { return }
        UserDefaults.standard.set(true, forKey: Self.startedKey)
        isStarted = true
        central = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey: Self.restoreID,
            CBCentralManagerOptionShowPowerAlertKey: false
        ])
    }

    /// Forgets the Mac and looks for it again (for when the Mac has been replaced).
    func forgetMac() {
        UserDefaults.standard.removeObject(forKey: Self.knownKey)
        if let mac { central?.cancelPeripheralConnection(mac) }
        mac = nil
        reconnect()
    }

    /// While the app is on screen, measure every second so the range screen feels live.
    func setLive(_ live: Bool) {
        liveTimer?.invalidate()
        liveTimer = nil
        guard live else { return }
        liveTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let mac = self?.mac, mac.state == .connected else { return }
            mac.readRSSI()
        }
    }

    private var knownID: UUID? {
        get { UserDefaults.standard.string(forKey: Self.knownKey).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: Self.knownKey) }
    }

    private func reconnect() {
        guard let central, central.state == .poweredOn else { return }
        if let mac, mac.state == .connected || mac.state == .connecting { return }
        // A standing request: iOS connects (and wakes Curfew) whenever the Mac comes into range.
        if let knownID, let known = central.retrievePeripherals(withIdentifiers: [knownID]).first {
            adopt(known)
            central.connect(known)
        } else if let already = central.retrieveConnectedPeripherals(withServices: [Signal.service]).first {
            adopt(already)
            central.connect(already)
        }
        // Also scan, in case the Mac's Bluetooth address has changed since last time.
        if !central.isScanning {
            central.scanForPeripherals(withServices: [Signal.service])
        }
    }

    private func adopt(_ peripheral: CBPeripheral) {
        mac = peripheral
        peripheral.delegate = self
        knownID = peripheral.identifier
    }

    private func record(_ rssi: Int) {
        // 127 means "no reading".
        guard rssi < 0, rssi > -120 else { return }
        samples.append(rssi)
        if samples.count > 4 { samples.removeFirst(samples.count - 4) }
        let average = samples.reduce(0, +) / samples.count
        strength = average
        update(heard: true)
    }

    private func update(heard: Bool) {
        let now = Date.now
        let before = SnapshotStore.load()
        let threshold = before.plan.threshold
        let wasIn = before.presence.isInBedroom(at: now)
        var inBedroom = false
        if heard, isConnected, let strength {
            // A little give either side, so standing near the edge doesn't flicker.
            inBedroom = wasIn ? strength >= threshold - 5 : strength >= threshold
        }
        let changed = inBedroom != wasIn
        // Save every change straight away, and otherwise once a minute to keep the reading fresh.
        guard changed || now.timeIntervalSince(lastSaved) > 60 || before.presence.macName != macName else { return }
        lastSaved = now
        SnapshotStore.update {
            $0.presence.inBedroom = inBedroom
            if heard { $0.presence.lastHeard = now }
            $0.presence.strength = strength
            $0.presence.macName = macName
        }
        if changed { onChange?() }
    }

    private func lost() {
        isConnected = false
        samples.removeAll()
        strength = nil
        update(heard: false)
    }
}

extension BedroomSensor: CBCentralManagerDelegate {
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first {
            adopt(restored)
            isConnected = restored.state == .connected
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetooth = central.state
        if central.state == .poweredOn {
            if let mac, mac.state == .connected {
                isConnected = true
                mac.discoverServices([Signal.service])
            }
            reconnect()
        } else {
            lost()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String, name != Signal.localName {
            macName = name
        }
        if mac?.identifier != peripheral.identifier || mac?.state == .disconnected {
            if let mac, mac.identifier != peripheral.identifier { central.cancelPeripheralConnection(mac) }
            adopt(peripheral)
            central.connect(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        central.stopScan()
        isConnected = true
        peripheral.discoverServices([Signal.service])
        peripheral.readRSSI()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        lost()
        reconnect()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        lost()
        reconnect()
    }
}

extension BedroomSensor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Signal.service }) else { return }
        peripheral.discoverCharacteristics([Signal.heartbeat], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let beat = service.characteristics?.first(where: { $0.uuid == Signal.heartbeat }) else { return }
        peripheral.setNotifyValue(true, for: beat)
        peripheral.readValue(for: beat)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Each heartbeat carries the Mac's name.
        if let data = characteristic.value, let name = String(data: data, encoding: .utf8), !name.isEmpty {
            macName = name
        }
        peripheral.readRSSI()
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        record(RSSI.intValue)
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        peripheral.discoverServices([Signal.service])
    }
}
