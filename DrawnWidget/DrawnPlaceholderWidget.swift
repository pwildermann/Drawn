import SwiftUI
import WidgetKit

private struct DrawnPlaceholderEntry: TimelineEntry {
    let date: Date
}

private struct DrawnPlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> DrawnPlaceholderEntry {
        DrawnPlaceholderEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (DrawnPlaceholderEntry) -> Void) {
        completion(DrawnPlaceholderEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DrawnPlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [DrawnPlaceholderEntry(date: Date())], policy: .never))
    }
}

struct DrawnPlaceholderWidget: Widget {
    let kind: String = "DrawnPlaceholderWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DrawnPlaceholderProvider()) { _ in
            Color.clear
        }
        .configurationDisplayName("Drawn")
        .description("Internal placeholder to keep widget descriptors stable.")
        .supportedFamilies([.systemSmall])
    }
}
