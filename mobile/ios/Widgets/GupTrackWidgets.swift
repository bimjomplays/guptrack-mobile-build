import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// GupTrack's widgets (65, 65b): Continue (medium, with +1 buttons), Next episode (small, and on the Lock Screen as a
// rectangle and a line) and Progress (a Lock Screen ring for a title in Continue). The faces are WidgetViews.swift;
// the numbers come from WidgetSnapshot (GupTrackKit, tested on Linux).
//
// Data: the library the app shares through the App Group (SharedBox: it rewrites it whenever the library changes and
// calls WidgetCenter.reloadAllTimelines()), with the +1s still waiting for the app on top. A +1 goes into the App
// Group's outbox, which the app sends to the server like any offline change when it next comes to the front.
// Without the App Group (unsigned simulator builds: the screen tests) the extension shows the demo it bundles and
// keeps its +1s in its own UserDefaults.

@main
struct GupTrackWidgets: WidgetBundle {
    var body: some Widget {
        ContinueWidget()
        NextEpisodeWidget()
        ProgressRingWidget()
    }
}

// MARK: data

/// what the widgets show: the app's shared library, or the bundled demo
enum WidgetStore {
    static var box: SharedBox? { SharedBox.app }
    static var defaults: UserDefaults { .standard }

    /// the demo's own +1s, when there is no App Group
    static func demoOutbox() -> WidgetOutbox { WidgetOutbox.load(defaults) }

    static func source() -> ExtensionSource {
        let source = ExtensionSource.current(box) {
            (ExtensionsJSON.bundledLibrary(),
             ExtensionsJSON.bundled(ExtensionCatalog.self, "extensions") ?? ExtensionCatalog())
        }
        // the demo data is recorded for Tue Nov 3, 2026, 9:41 AM in New York, so the demo runs on that clock
        Clock.fixed = source.demo ? Clock.demoNow : nil
        Clock.fixedZone = source.demo ? Clock.demoZone : nil
        return source
    }

    static func snapshot() -> WidgetSnapshot {
        let s = source()
        let lib = s.usesBox ? s.library : demoOutbox().apply(to: s.library)
        return WidgetSnapshot.make(library: lib, catalog: s.catalog, now: Clock.now)
    }

    /// a +1 from a widget's button
    static func step(_ id: String) {
        let s = source()
        if let box, s.usesBox {
            guard s.signedIn else { return }
            box.step(id, in: ExtensionSource.base(box), now: Clock.now)
        } else {
            var outbox = demoOutbox()
            if outbox.step(id, in: s.library, now: Clock.now) != nil { outbox.save(defaults) }
        }
    }
}

/// a timeline entry: the snapshot and the covers it shows, downloaded first (a widget can't load pictures while
/// it's drawn)
struct WidgetArtEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let images: [URL: UIImage]

    static func load() async -> WidgetArtEntry {
        let snap = WidgetStore.snapshot()
        let urls = snap.items.prefix(2).compactMap(\.cover) + [snap.spotlight?.cover].compactMap { $0 }
        return WidgetArtEntry(date: Date(), snapshot: snap, images: await images(urls, account: SharedAccount.load()))
    }

    /// GupTrack's own pictures ("/media/…") come from the signed-in server, with the token (SharedAccount)
    static func images(_ urls: [URL], account: SharedAccount?) async -> [URL: UIImage] {
        await withTaskGroup(of: (URL, UIImage?).self) { group in
            for url in Set(urls) {
                let request = account?.request(for: url) ?? URLRequest(url: url)
                group.addTask { (url, await fetch(request)) }
            }
            var out: [URL: UIImage] = [:]
            for await (url, image) in group {
                if let image { out[url] = image }
            }
            return out
        }
    }

    /// a cover, made small (widgets have little memory)
    static func fetch(_ request: URLRequest) async -> UIImage? {
        var request = request
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 8
        guard request.url?.scheme != nil else { return nil }
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
        WidgetArtEntry(date: Date(), snapshot: WidgetStore.snapshot(), images: [:])
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
        WidgetStore.step(titleID)
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
        RingEntry(date: Date(), item: WidgetStore.snapshot().items.first)
    }

    func snapshot(for configuration: RingSlotIntent, in context: Context) async -> RingEntry {
        entry(configuration)
    }

    func timeline(for configuration: RingSlotIntent, in context: Context) async -> Timeline<RingEntry> {
        Timeline(entries: [entry(configuration)], policy: .after(Date().addingTimeInterval(3600)))
    }

    private func entry(_ configuration: RingSlotIntent) -> RingEntry {
        let items = WidgetStore.snapshot().items
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
