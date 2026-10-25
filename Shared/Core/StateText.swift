import Foundation

/// Words and symbols for each state, shared by the app and the widget.
extension CurfewState {
    var title: String {
        switch self {
        case .off: "Curfew is off"
        case .locked: "Apps locked"
        case .onBreak: "On a break"
        case .inBedroomFree: "In the bedroom"
        case .away: "Not in the bedroom"
        case .idle: "Free time"
        }
    }

    /// A short line for small spaces.
    var shortTitle: String {
        switch self {
        case .off: "Off"
        case .locked: "Locked"
        case .onBreak: "Break"
        case .inBedroomFree: "Bedroom"
        case .away: "Away"
        case .idle: "Free"
        }
    }

    var detail: String {
        switch self {
        case .off:
            return "Turn it on to lock your apps at bedtime."
        case .locked(let until):
            guard let until else { return "Until you leave the bedroom." }
            return "Until \(Self.time(until)), or until you leave the bedroom."
        case .onBreak(let until):
            return "Apps lock again at \(Self.time(until))."
        case .inBedroomFree(let locksAt):
            guard let locksAt else { return "No bedtime set." }
            return "Apps lock \(Self.when(locksAt))."
        case .away(let untilEnd):
            guard let untilEnd else { return "Apps lock when you go into the bedroom." }
            return "Apps lock if you go into the bedroom before \(Self.time(untilEnd))."
        case .idle(let nextStart):
            guard let nextStart else { return "No bedtime set." }
            return "Bedtime starts \(Self.when(nextStart))."
        }
    }

    var symbol: String {
        switch self {
        case .off: "moon.zzz"
        case .locked: "lock.fill"
        case .onBreak: "cup.and.heat.waves.fill"
        case .inBedroomFree: "bed.double.fill"
        case .away: "figure.walk"
        case .idle: "sun.max.fill"
        }
    }

    /// When the state next changes by the clock alone.
    var nextChange: Date? {
        switch self {
        case .off: nil
        case .locked(let until): until
        case .onBreak(let until): until
        case .inBedroomFree(let at): at
        case .away(let until): until
        case .idle(let at): at
        }
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "at 22:00", "tomorrow at 22:00" or "on Friday at 22:00".
    static func when(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "at \(time(date))" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow at \(time(date))"
        }
        return "on \(date.formatted(.dateTime.weekday(.wide))) at \(time(date))"
    }
}
