import SwiftUI

enum Theme {
    static let accent = Color("AccentColor")
    static let midnight = Color(red: 0.06, green: 0.07, blue: 0.18)
    static let dusk = Color(red: 0.20, green: 0.16, blue: 0.42)
    static let moon = Color(red: 1.0, green: 0.86, blue: 0.62)

    /// The hero card's background for each state.
    static func background(for state: CurfewState) -> LinearGradient {
        let colours: [Color] = switch state {
        case .locked: [dusk, midnight]
        case .onBreak: [Color(red: 0.36, green: 0.24, blue: 0.48), Color(red: 0.14, green: 0.10, blue: 0.26)]
        case .inBedroomFree: [Color(red: 0.24, green: 0.27, blue: 0.56), Color(red: 0.10, green: 0.12, blue: 0.30)]
        case .away, .idle: [Color(red: 0.30, green: 0.36, blue: 0.62), Color(red: 0.16, green: 0.20, blue: 0.40)]
        case .off: [Color(white: 0.36), Color(white: 0.20)]
        }
        return LinearGradient(colors: colours, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// A round "signal strength" meter with a needle for where the bedroom starts.
struct SignalMeter: View {
    let strength: Int?
    let threshold: Int

    /// -100 dBm to -35 dBm, shown left to right.
    private func position(_ value: Int) -> Double { min(1, max(0, Double(value + 100) / 65)) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if let strength {
                    Capsule()
                        .fill(strength >= threshold ? Theme.accent : .secondary)
                        .frame(width: max(8, proxy.size.width * position(strength)))
                        .animation(.smooth, value: strength)
                }
                Rectangle()
                    .fill(.primary)
                    .frame(width: 2, height: proxy.size.height + 6)
                    .offset(x: proxy.size.width * position(threshold) - 1)
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Signal")
        .accessibilityValue(strength.map { $0 >= threshold ? "In the bedroom, \($0) dBm" : "Outside, \($0) dBm" } ?? "No signal")
    }
}
