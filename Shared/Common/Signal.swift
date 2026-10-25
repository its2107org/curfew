import CoreBluetooth

/// The Bluetooth signal the Mac gives off and the iPhone listens for.
///
/// The Mac advertises one service. The iPhone connects to it and subscribes to a "heartbeat"
/// that the Mac sends every few seconds; each beat wakes the iPhone briefly so it can measure
/// how strong the signal is (which says roughly how close the Mac is).
enum Signal {
    static let service = CBUUID(string: "6E0C2F4A-8B3D-4F1E-9C27-5A1D3B0E7C11")
    static let heartbeat = CBUUID(string: "6E0C2F4A-8B3D-4F1E-9C27-5A1D3B0E7C12")
    static let localName = "Curfew"
    /// Seconds between heartbeats.
    static let beatInterval: TimeInterval = 15
}
