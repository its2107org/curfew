import SwiftUI

/// Sets the start and end time of a bedtime window and the nights it applies.
struct WindowEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var window: BedtimeWindow
    let isNew: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Starts", selection: time(\.start), displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: time(\.end), displayedComponents: .hourAndMinute)
                } footer: {
                    if window.length < 15 {
                        Text("Make it at least 15 minutes long.")
                    } else if window.crossesMidnight {
                        Text("Ends the next morning.")
                    }
                }

                Section {
                    DayChips(days: $window.days)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    HStack {
                        quick("Every day", Set(1...7))
                        quick("School nights", [1, 2, 3, 4, 5])
                        quick("Weekends", [6, 7])
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } header: {
                    Text("Nights")
                } footer: {
                    Text("Pick the day each window starts on. A window from 22:00 on Sunday runs into Monday morning.")
                }

                if !isNew {
                    Section {
                        Button("Delete this time", role: .destructive) {
                            model.deleteWindow(window.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New time" : "Edit time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.saveWindow(window)
                        dismiss()
                    }
                    .disabled(window.days.isEmpty || window.length < 15)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func quick(_ title: String, _ days: Set<Int>) -> some View {
        Button(title) { window.days = days }
            .tint(window.days == days ? Theme.accent : .secondary)
    }

    /// A clock-time binding for minutes after midnight.
    private func time(_ key: WritableKeyPath<BedtimeWindow, Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(byAdding: .minute, value: window[keyPath: key], to: Calendar.current.startOfDay(for: .now)) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            window[keyPath: key] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}

/// Seven round buttons, Monday first.
struct DayChips: View {
    @Binding var days: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let names = Calendar.current.weekdaySymbols
        HStack(spacing: 6) {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                let on = days.contains(day)
                Button {
                    if on { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(on ? .white : .primary)
                        .background(on ? AnyShapeStyle(Theme.accent.gradient) : AnyShapeStyle(.quaternary), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(names[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: days)
    }
}
