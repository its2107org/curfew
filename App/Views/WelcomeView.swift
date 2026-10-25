import SwiftUI

/// First-run set-up: Screen Time, Bluetooth, then the Mac.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(Theme.moon)
                        .padding(.bottom, 6)
                    Text("Curfew")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Locks the apps you choose at bedtime, while you're in the bedroom.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .foregroundStyle(.white)
                .padding(.top, 40)

                VStack(spacing: 12) {
                    StepCard(number: 1, title: "Allow Screen Time",
                             detail: "So Curfew can lock apps.",
                             done: model.canBlock, waiting: model.screenTimeError != nil) {
                        Task { await model.askForScreenTime() }
                    }
                    StepCard(number: 2, title: "Allow Bluetooth",
                             detail: "So your iPhone can hear your Mac.",
                             done: model.sensor.isStarted && model.sensor.bluetooth == .poweredOn, waiting: false) {
                        model.sensor.start()
                    }
                    StepCard(number: 3, title: "Open Curfew on your Mac",
                             detail: model.sensor.isConnected ? "Found \(model.sensor.macName ?? "your Mac")." : "Install it from TestFlight on the Mac and open it once.",
                             done: model.sensor.isConnected, waiting: model.sensor.isStarted && !model.sensor.isConnected, action: nil)
                }

                if let error = model.screenTimeError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Button {
                    model.hasFinishedSetup = true
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.moon)
                .foregroundStyle(Theme.midnight)
                .controlSize(.large)
            }
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(LinearGradient(colors: [Theme.dusk, Theme.midnight], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }
}

struct StepCard: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool
    let waiting: Bool
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(done ? AnyShapeStyle(Color.green.gradient) : AnyShapeStyle(.white.opacity(0.14)))
                if done {
                    Image(systemName: "checkmark").font(.headline.weight(.bold))
                } else {
                    Text("\(number)").font(.headline)
                }
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            if !done {
                if let action {
                    Button(waiting ? "Retry" : "Allow", action: action)
                        .buttonStyle(.bordered)
                        .tint(.white)
                } else if waiting {
                    ProgressView().tint(.white)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 20))
    }
}
