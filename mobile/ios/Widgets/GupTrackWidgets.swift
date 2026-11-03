import SwiftUI
import WidgetKit

/// Up Next widgets (65, 65b). A placeholder until the widget views land.
@main
struct GupTrackWidgets: WidgetBundle {
    var body: some Widget { UpNextWidget() }
}

struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpNext", provider: Provider()) { _ in
            Text("Up Next").containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Up Next")
    }
}

struct Provider: TimelineProvider {
    struct Entry: TimelineEntry { let date: Date }
    func placeholder(in context: Context) -> Entry { Entry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}
