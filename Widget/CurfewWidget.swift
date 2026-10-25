import SwiftUI
import WidgetKit

@main
struct CurfewWidgets: WidgetBundle {
    var body: some Widget {
        CurfewWidget()
    }
}

struct CurfewEntry: TimelineEntry {
    let date: Date
    let state: CurfewState
}

struct CurfewProvider: TimelineProvider {
    func placeholder(in context: Context) -> CurfewEntry {
        CurfewEntry(date: .now, state: .locked(until: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now)))
    }

    func getSnapshot(in context: Context, completion: @escaping (CurfewEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : CurfewEntry(date: .now, state: SnapshotStore.load().state()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CurfewEntry>) -> Void) {
        // An entry now and at each upcoming change by the clock. The app and the monitor
        // refresh the widget whenever the bedroom reading changes.
        let snapshot = SnapshotStore.load()
        var entries = [CurfewEntry(date: .now, state: snapshot.state())]
        var cursor = Date.now
        for _ in 0..<6 {
            guard let next = [snapshot.plan.nextEdge(after: cursor), snapshot.breakUntil].compactMap({ $0 }).filter({ $0 > cursor }).min() else { break }
            let at = next.addingTimeInterval(1)
            entries.append(CurfewEntry(date: at, state: snapshot.state(at: at)))
            cursor = at
        }
        completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(60 * 60))))
    }
}

struct CurfewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CurfewStatus", provider: CurfewProvider()) { entry in
            CurfewWidgetView(entry: entry)
                .widgetURL(URL(string: "curfew://home"))
        }
        .configurationDisplayName("Curfew")
        .description("Whether your apps are locked, and when bedtime starts.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CurfewWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CurfewEntry

    private var midnight: Color { Color(red: 0.06, green: 0.07, blue: 0.18) }
    private var dusk: Color { Color(red: 0.20, green: 0.16, blue: 0.42) }
    private var moon: Color { Color(red: 1.0, green: 0.86, blue: 0.62) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: entry.state.symbol).font(.title2.weight(.semibold))
            }
            .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(entry.state.title, systemImage: entry.state.symbol)
                    .font(.headline)
                    .widgetAccentable()
                Text(entry.state.detail)
                    .font(.caption)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            Label(inline, systemImage: entry.state.symbol)
                .containerBackground(.clear, for: .widget)
        default:
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: entry.state.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(moon)
                Spacer()
                Text(entry.state.title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.8)
                Text(entry.state.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(3)
                    .padding(.top, 2)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) {
                LinearGradient(colors: entry.state == .off ? [Color(white: 0.36), Color(white: 0.2)] : [dusk, midnight],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    private var inline: String {
        if let next = entry.state.nextChange {
            return "\(entry.state.shortTitle) · \(CurfewState.time(next))"
        }
        return entry.state.shortTitle
    }
}
