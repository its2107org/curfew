import FamilyControls
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var pickingApps = false
    @State private var editing: BedtimeWindow?
    @State private var settingRange = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section {
                    HeroCard(state: model.state, isOn: Binding(
                        get: { model.plan.isOn },
                        set: { on in model.change { $0.isOn = on } }
                    ))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    if case .locked = model.state {
                        BreakButton(minutes: Int(model.plan.breakLength / 60)) { model.takeBreak() }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
                    }
                    if case .onBreak = model.state {
                        Button("End the break now") { model.endBreak() }
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                }

                if !model.canBlock {
                    Section {
                        WaitingNote()
                    }
                }

                appsSection
                timesSection
                bedroomSection
            }
            .listSectionSpacing(.compact)
            .navigationTitle("Curfew")
            .familyActivityPicker(isPresented: $pickingApps, selection: $model.selection)
            .onChange(of: model.selection) { _, new in model.saveSelection(new) }
            .sheet(item: $editing) { window in
                WindowEditor(window: window, isNew: !model.plan.windows.contains { $0.id == window.id })
            }
            .sheet(isPresented: $settingRange) { RangeView() }
            .onAppear {
                if Demo.openWindow { editing = model.plan.windows.first }
                if Demo.openRange { settingRange = true }
            }
        }
    }

    // MARK: - Apps

    private var appsSection: some View {
        Section {
            Button {
                if model.canBlock { pickingApps = true } else { Task { await model.askForScreenTime() } }
            } label: {
                HStack(spacing: 12) {
                    RowIcon(symbol: "square.grid.2x2.fill", colour: .indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Choose apps").foregroundStyle(.primary)
                        Text(model.plan.chosenCount == 0 ? "Nothing chosen yet" : model.plan.chosenSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ChosenIcons(selection: model.selection)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Picker("What to lock", selection: Binding(
                get: { model.plan.style },
                set: { style in model.change { $0.style = style } }
            )) {
                Text("Just these").tag(BlockStyle.chosen)
                Text("All but these").tag(BlockStyle.allExceptChosen)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Apps")
        } footer: {
            Text(model.plan.style == .chosen
                 ? "These apps lock at bedtime."
                 : "Everything locks at bedtime except these apps (and Phone, which always works).")
        }
    }

    // MARK: - Times

    private var timesSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { model.plan.anyTime },
                set: { any in model.change { $0.anyTime = any } }
            )) {
                HStack(spacing: 12) {
                    RowIcon(symbol: "infinity", colour: .teal)
                    Text("Any time I'm in the bedroom")
                }
            }

            if !model.plan.anyTime {
                ForEach(model.plan.windows) { window in
                    WindowRow(window: window) { editing = window }
                        .swipeActions {
                            Button("Delete", role: .destructive) { model.deleteWindow(window.id) }
                        }
                }
                Button {
                    editing = BedtimeWindow(start: 22 * 60, end: 7 * 60)
                } label: {
                    Label("Add a time", systemImage: "plus")
                }
            }
        } header: {
            Text("Times")
        } footer: {
            if !model.plan.anyTime {
                Text("Apps lock during these times, but only while you're in the bedroom.")
            }
        }
    }

    // MARK: - Bedroom

    private var bedroomSection: some View {
        Section {
            HStack(spacing: 12) {
                RowIcon(symbol: "macmini.fill", colour: .gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text(macTitle)
                    Text(macDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if connected {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                }
            }

            Button {
                settingRange = true
            } label: {
                HStack(spacing: 12) {
                    RowIcon(symbol: "scope", colour: .orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bedroom range").foregroundStyle(.primary)
                        SignalMeter(strength: strength, threshold: model.plan.threshold)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Bedroom")
        } footer: {
            Text("Your iPhone listens for Curfew on your Mac. Keep Curfew open on the Mac, and don't swipe Curfew away on your iPhone.")
        }
    }

    private var connected: Bool { model.sensor.isConnected || SnapshotStore.isDemo && model.snapshot.presence.inBedroom }
    private var strength: Int? { model.sensor.strength ?? (SnapshotStore.isDemo ? model.snapshot.presence.strength : nil) }

    private var macTitle: String {
        if connected { return model.sensor.macName ?? model.snapshot.presence.macName ?? "Mac found" }
        return "Looking for your Mac"
    }

    private var macDetail: String {
        if !SnapshotStore.isDemo {
            switch model.sensor.bluetooth {
            case .poweredOff: return "Bluetooth is off. Turn it on in Control Centre."
            case .unauthorized: return "Bluetooth isn't allowed. Turn it on in Settings > Curfew."
            default: break
            }
        }
        if connected {
            return model.snapshot.presence.isInBedroom(at: model.now) ? "Close by: you're in the bedroom" : "In range, but outside the bedroom"
        }
        return "Out of range, or Curfew isn't open on the Mac"
    }
}

// MARK: - Pieces

struct HeroCard: View {
    let state: CurfewState
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Image(systemName: state.symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.moon)
                    .symbolEffect(.bounce, value: state.shortTitle)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(height: 44)
                Spacer()
                Toggle("Curfew on", isOn: $isOn)
                    .labelsHidden()
                    .tint(Theme.moon.opacity(0.9))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(state.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .contentTransition(.opacity)
                Text(state.detail)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background(for: state), in: .rect(cornerRadius: 28))
        .overlay(alignment: .topTrailing) { Stars().allowsHitTesting(false) }
        .animation(.smooth, value: state)
        .accessibilityElement(children: .contain)
    }
}

/// A few faint stars in the hero card.
struct Stars: View {
    var body: some View {
        Canvas { context, size in
            let points: [(CGFloat, CGFloat, CGFloat)] = [(0.55, 0.18, 2), (0.70, 0.42, 1.5), (0.82, 0.70, 2.2), (0.62, 0.80, 1.2), (0.46, 0.55, 1)]
            for (x, y, r) in points {
                let rect = CGRect(x: size.width * x, y: size.height * y, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.35)))
            }
        }
        .frame(width: 160, height: 120)
        .padding(.trailing, 70)
    }
}

/// Press and hold to unlock for a short break, so it isn't done on a whim.
struct BreakButton: View {
    let minutes: Int
    let action: () -> Void
    @State private var progress: CGFloat = 0
    @State private var holding = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap")
            Text(holding ? "Keep holding…" : "Hold for a \(minutes)-minute break")
        }
        .font(.callout.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.thinMaterial)
                    Capsule().fill(Theme.accent.opacity(0.35)).frame(width: proxy.size.width * progress)
                }
            }
        }
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: 3) {
            action()
            progress = 0
        } onPressingChanged: { pressing in
            holding = pressing
            withAnimation(pressing ? .linear(duration: 3) : .easeOut(duration: 0.2)) { progress = pressing ? 1 : 0 }
        }
        .sensoryFeedback(.success, trigger: progress == 1)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

struct WaitingNote: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Waiting for Apple", systemImage: "hourglass")
                .font(.headline)
            Text(model.screenTimeError ?? "Apple has to allow Curfew to lock apps. Until then, Curfew shows when you're in the bedroom but doesn't lock anything.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Try again") { Task { await model.askForScreenTime() } }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}

struct RowIcon: View {
    let symbol: String
    let colour: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(colour.gradient, in: .rect(cornerRadius: 8))
    }
}

struct ChosenIcons: View {
    let selection: FamilyActivitySelection

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(selection.applicationTokens.prefix(4)), id: \.self) { token in
                Label(token)
                    .labelStyle(.iconOnly)
                    .frame(width: 26, height: 26)
                    .clipShape(.rect(cornerRadius: 6))
            }
        }
    }
}

struct WindowRow: View {
    let window: BedtimeWindow
    let edit: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Button(action: edit) {
                HStack(spacing: 12) {
                    RowIcon(symbol: window.start >= 18 * 60 || window.start < 4 * 60 ? "moon.stars.fill" : "clock.fill", colour: .purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(window.timesText)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(window.isOn ? .primary : .secondary)
                        Text(window.daysText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Toggle("On", isOn: Binding(
                get: { window.isOn },
                set: { on in var changed = window; changed.isOn = on; model.saveWindow(changed) }
            ))
            .labelsHidden()
        }
    }
}
