import WidgetKit
import SwiftUI

private let group = "group.com.kayloehmann.opengym.kraftplanwatch"

struct KraftplanEntry: TimelineEntry {
    let date: Date
    let active: Bool
    let title: String
    let completed: Int
    let total: Int
    let weekDone: Int
    let weekTarget: Int
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> KraftplanEntry { .init(date: Date(), active: false, title: "Heute", completed: 0, total: 5, weekDone: 2, weekTarget: 3) }
    func getSnapshot(in context: Context, completion: @escaping (KraftplanEntry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<KraftplanEntry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
    private func read() -> KraftplanEntry {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: "context"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .init(date: Date(), active: false, title: "Kraftplan", completed: 0, total: 0, weekDone: 0, weekTarget: 0)
        }
        let active = root["state"] as? String == "active"
        let workout = root["workout"] as? [String: Any]
        let exercises = workout?["exercises"] as? [[String: Any]] ?? []
        let sets = exercises.flatMap { $0["sets"] as? [[String: Any]] ?? [] }
        let week = root["week"] as? [String: Any] ?? [:]
        return .init(date: Date(), active: active, title: workout?["name"] as? String ?? "Kraftplan",
                     completed: sets.filter { $0["done"] as? Bool == true }.count, total: sets.count,
                     weekDone: week["completed"] as? Int ?? 0, weekTarget: week["target"] as? Int ?? 0)
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: KraftplanEntry
    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(entry.active ? entry.completed : entry.weekDone), in: 0...Double(max(1, entry.active ? entry.total : entry.weekTarget))) {
                Image(systemName: "figure.strengthtraining.traditional")
            }.gaugeStyle(.accessoryCircularCapacity)
        case .accessoryInline:
            Text(entry.active ? "\(entry.completed)/\(entry.total) Sätze" : "Woche \(entry.weekDone)/\(entry.weekTarget)")
                .minimumScaleFactor(0.7)
        default:
            VStack(alignment: .leading, spacing: 2) {
                Label(entry.active ? "Training" : "Kraftplan", systemImage: "figure.strengthtraining.traditional")
                    .minimumScaleFactor(0.7)
                Text(entry.active ? "\(entry.completed)/\(entry.total) Sätze" : "Woche \(entry.weekDone)/\(entry.weekTarget)")
                    .font(.caption2).foregroundStyle(.secondary).minimumScaleFactor(0.7)
                ProgressView(value: Double(entry.active ? entry.completed : entry.weekDone), total: Double(max(1, entry.active ? entry.total : entry.weekTarget))).tint(.orange)
            }
        }
    }
}

@main
struct KraftplanComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KraftplanComplication", provider: Provider()) { entry in
            ComplicationView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Kraftplan")
        .description("Trainingsfortschritt heute und in dieser Woche.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
