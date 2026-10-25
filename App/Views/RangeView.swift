import SwiftUI

/// Teaches Curfew where the bedroom ends: measure by the bed, then just outside the door.
struct RangeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var inside: Int?
    @State private var outside: Int?
    @State private var measuring: Spot?
    @State private var threshold: Double = -72

    enum Spot { case inside, outside }

    private var strength: Int? { model.sensor.strength ?? (SnapshotStore.isDemo ? -58 : nil) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: strength != nil)
                        Text(strength.map(label) ?? "No signal from the Mac")
                            .font(.title3.weight(.semibold))
                        SignalMeter(strength: strength, threshold: Int(threshold))
                            .padding(.horizontal, 8)
                        Text(strength != nil && strength! >= Int(threshold) ? "Counts as in the bedroom" : "Counts as outside")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }

                Section {
                    measureRow(.inside, title: "1. Stand by your bed", value: inside)
                    measureRow(.outside, title: "2. Stand just outside the bedroom door", value: outside)
                } header: {
                    Text("Set it up")
                } footer: {
                    Text("Hold your iPhone as you normally would. Each measurement takes five seconds.")
                }

                Section {
                    Slider(value: $threshold, in: -95 ... -45, step: 1) {
                        Text("Range")
                    } minimumValueLabel: {
                        Text("Bigger").font(.caption)
                    } maximumValueLabel: {
                        Text("Smaller").font(.caption)
                    }
                } header: {
                    Text("Fine-tune")
                } footer: {
                    Text("Slide left if Curfew misses you in bed. Slide right if it locks while you're outside the room.")
                }
            }
            .navigationTitle("Bedroom range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.change { $0.threshold = Int(threshold) }
                        dismiss()
                    }
                }
            }
            .onAppear {
                threshold = Double(model.plan.threshold)
                model.sensor.setLive(true)
            }
            .onDisappear { model.sensor.setLive(false) }
        }
    }

    private func label(_ value: Int) -> String {
        switch value {
        case -55...: "Very close"
        case -68 ..< -55: "Close"
        case -80 ..< -68: "Nearby"
        default: "Far away"
        }
    }

    private func measureRow(_ spot: Spot, title: String, value: Int?) -> some View {
        HStack {
            Text(title)
            Spacer()
            if measuring == spot {
                ProgressView()
            } else if value != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Measure") { measure(spot) }
                    .buttonStyle(.bordered)
                    .disabled(strength == nil || measuring != nil)
            }
        }
    }

    private func measure(_ spot: Spot) {
        measuring = spot
        Task {
            var readings: [Int] = []
            for _ in 0..<5 {
                try? await Task.sleep(for: .seconds(1))
                if let strength { readings.append(strength) }
            }
            measuring = nil
            guard !readings.isEmpty else { return }
            let average = readings.reduce(0, +) / readings.count
            if spot == .inside { inside = average } else { outside = average }
            if let inside, let outside {
                // Halfway between, leaning towards the inside reading if the two are close.
                let middle = inside > outside + 4 ? (inside + outside) / 2 : inside - 6
                threshold = Double(min(-45, max(-95, middle)))
            } else if let inside {
                threshold = Double(min(-45, max(-95, inside - 8)))
            }
        }
    }
}
