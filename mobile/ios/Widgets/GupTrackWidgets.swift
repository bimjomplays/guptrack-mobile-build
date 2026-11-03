import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// GupTrack's widgets (65, 65b): Continue (medium, with +1 buttons), Next episode (small, and on the Lock Screen as a
// rectangle and a line) and Progress (a Lock Screen ring for a title in Continue). The faces are WidgetViews.swift;
// the numbers come from WidgetSnapshot (GupTrackKit, tested on Linux).
//
// Demo: the extension reads the library and api/extensions.json bundled into it, and keeps its +1s in its own
// UserDefaults (WidgetOutbox). For the real app this moves to an App Group shared with the app: the app writes the
// library (or the snapshot) there whenever it changes and calls WidgetCenter.reloadAllTimelines(); a +1 goes into the
// App Group's outbox, which the app sends to the server like any offline change. An App Group needs the signing
// team, so it waits for the signed build.

@main
struct GupTrackWidgets: WidgetBundle {
    var body: some Widget {
        ContinueWidget()
        NextEpisodeWidget()
        ProgressRingWidget()
    }
}

// MARK: data

/// the demo's library and catalogue, read from the extension's bundle, with the widget's own +1s on top
enum WidgetDemoStore {
    static var defaults: UserDefaults { .standard }

    /// the demo data is recorded for Tue Nov 3, 2026, 9:41 AM in New York, so the widgets run on that clock
    static func useDemoClock() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    static func baseLibrary() -> [LibraryEntry] {
        ExtensionsJSON.bundledLibrary()
    }

    static func catalog() -> ExtensionCatalog {
        ExtensionsJSON.bundled(ExtensionCatalog.self, "extensions") ?? ExtensionCatalog()
    }

    static func snapshot() -> WidgetSnapshot {
        useDemoClock()
        let lib = WidgetOutbox.load(defaults).apply(to: baseLibrary())
        return WidgetSnapshot.make(library: lib, catalog: catalog(), now: Clock.now)
    }

    /// a +1 from a widget's button
    static func step(_ id: String) {
        useDemoClock()
        var box = WidgetOutbox.load(defaults)
        if box.step(id, in: baseLibrary(), now: Clock.now) != nil { box.save(defaults) }
    }
}

/// a timeline entry: the snapshot and the covers it shows, downloaded first (a widget can't load pictures while
/// it's drawn)
struct WidgetArtEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let images: [URL: UIImage]

    static func load() async -> WidgetArtEntry {
        let snap = WidgetDemoStore.snapshot()
        let urls = snap.items.prefix(2).compactMap(\.cover) + [snap.spotlight?.cover].compactMap { $0 }
        return WidgetArtEntry(date: Date(), snapshot: snap, images: await images(urls))
    }

    static func images(_ urls: [URL]) async -> [URL: UIImage] {
        await withTaskGroup(of: (URL, UIImage?).self) { group in
            for url in Set(urls) {
                group.addTask { (url, await fetch(url)) }
            }
            var out: [URL: UIImage] = [:]
            for await (url, image) in group {
                if let image { out[url] = image }
            }
            return out
        }
    }

    /// a cover, made small (widgets have little memory)
    static func fetch(_ url: URL) async -> UIImage? {
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
        guard let (data, _) = try? await URLSession.shared.data(for: request), let image = UIImage(data: data) else {
            return nil
        }
        let longest = max(image.size.width, image.size.height)
        guard longest > 400 else { return image }
        let scale = 400 / longest
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        return image.preparingThumbnail(of: size) ?? image
    }
}

struct WidgetArtProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetArtEntry {
        WidgetArtEntry(date: Date(), snapshot: WidgetDemoStore.snapshot(), images: [:])
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetArtEntry) -> Void) {
        Task { completion(await WidgetArtEntry.load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetArtEntry>) -> Void) {
        Task {
            let entry = await WidgetArtEntry.load()
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
        }
    }
}

/// a downloaded cover, or a grey tile while there isn't one
struct WidgetArt: View {
    let image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Rectangle().fill(Color(white: 0.17))
        }
    }
}

// MARK: +1

/// the +1 on a Continue row: adds an episode (a chapter, 10 pages) and the widget redraws
struct IncrementProgressIntent: AppIntent {
    static var title: LocalizedStringResource = "Add one"
    static var description = IntentDescription("Adds an episode, a chapter or 10 pages to a title in Continue.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "Title")
    var titleID: String

    init() {}

    init(titleID: String) {
        self.titleID = titleID
    }

    func perform() async throws -> some IntentResult {
        WidgetDemoStore.step(titleID)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: Continue (medium)

struct ContinueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "continue", provider: WidgetArtProvider()) { entry in
            ContinueWidgetView(snapshot: entry.snapshot, art: { WidgetArt(image: $0.flatMap { entry.images[$0] }) },
                               plus: { item in
                                   Button(intent: IncrementProgressIntent(titleID: item.id)) { WidgetPlusLabel() }
                                       .buttonStyle(.plain)
                               })
                .containerBackground(for: .widget) { WidgetInk.background }
        }
        .configurationDisplayName("Continue")
        .description("What you're watching and reading, with +1 to log the next one.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: Next episode (small, Lock Screen rectangle and line)

struct NextEpisodeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "next-episode", provider: WidgetArtProvider()) { entry in
            NextEpisodeEntryView(entry: entry)
        }
        .configurationDisplayName("Next episode")
        .description("When the next episode of what you watch comes out.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct NextEpisodeEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetArtEntry

    var body: some View {
        content.widgetURL(entry.snapshot.spotlight?.url ?? URL(string: "guptrack://calendar"))
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryRectangular:
            ZStack {
                AccessoryWidgetBackground()
                NextEpisodeAccessoryView(spotlight: entry.snapshot.spotlight)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            NextEpisodeInlineView(spotlight: entry.snapshot.spotlight)
                .containerBackground(.clear, for: .widget)
        default:
            NextEpisodeWidgetView(spotlight: entry.snapshot.spotlight,
                                  art: { WidgetArt(image: $0.flatMap { entry.images[$0] }) })
                .containerBackground(for: .widget) { Color.black }
        }
    }
}

// MARK: Progress ring (Lock Screen circle)

/// which title in Continue a ring shows
enum ContinueSlot: String, AppEnum {
    case first, second, third, fourth

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Title in Continue"
    static var caseDisplayRepresentations: [ContinueSlot: DisplayRepresentation] = [
        .first: "First", .second: "Second", .third: "Third", .fourth: "Fourth",
    ]

    var index: Int {
        switch self {
        case .first: return 0
        case .second: return 1
        case .third: return 2
        case .fourth: return 3
        }
    }
}

struct RingSlotIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Progress"
    static var description = IntentDescription("Which title in Continue the ring follows.")

    @Parameter(title: "Title in Continue", default: .first)
    var slot: ContinueSlot
}

struct RingEntry: TimelineEntry {
    let date: Date
    let item: WidgetSnapshot.Item?
}

struct RingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RingEntry {
        RingEntry(date: Date(), item: WidgetDemoStore.snapshot().items.first)
    }

    func snapshot(for configuration: RingSlotIntent, in context: Context) async -> RingEntry {
        entry(configuration)
    }

    func timeline(for configuration: RingSlotIntent, in context: Context) async -> Timeline<RingEntry> {
        Timeline(entries: [entry(configuration)], policy: .after(Date().addingTimeInterval(3600)))
    }

    private func entry(_ configuration: RingSlotIntent) -> RingEntry {
        let items = WidgetDemoStore.snapshot().items
        let i = configuration.slot.index
        return RingEntry(date: Date(), item: i < items.count ? items[i] : nil)
    }
}

struct ProgressRingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "progress-ring", intent: RingSlotIntent.self, provider: RingProvider()) { entry in
            ZStack {
                AccessoryWidgetBackground()
                ProgressRingAccessoryView(item: entry.item)
            }
            .widgetURL(entry.item?.url ?? URL(string: "guptrack://list/anime"))
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Progress")
        .description("A ring of how far you are in a title from Continue.")
        .supportedFamilies([.accessoryCircular])
    }
}
