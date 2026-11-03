import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// The Library tab's logic on the demo library (32-40).
final class LibraryListsTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func library() throws -> [LibraryEntry] { try Demo.load([LibraryEntry].self, "api/library.json") }

    private func entry(_ name: String, media: MediaKind = .anime, format: String? = "TV", total: Int? = 12,
                       status: ListStatus = .current, progress: Int = 0, score: Int? = nil, runtime: String? = nil,
                       daysAgo: Double = 1) -> LibraryEntry {
        let t = Title(id: "\(media.rawValue):\(name)", media: media, name: name, format: format, total: total,
                      runtime: runtime)
        return LibraryEntry(title: t, status: status, progress: progress, score: score,
                            updatedAt: Clock.demoNow.addingTimeInterval(-daysAgo * 86_400))
    }

    // MARK: 32 the root

    func testRootCountsEachMedia() throws {
        let lib = try library()
        XCTAssertEqual(LibraryLists.mediaLine(lib, media: .anime), "7 watching")
        XCTAssertEqual(LibraryLists.mediaLine(lib, media: .manga), "1 reading")
        XCTAssertEqual(LibraryLists.mediaLine(lib, media: .tv), "1 watching")
        XCTAssertEqual(LibraryLists.mediaLine(lib, media: .movie), "9 watched")
        XCTAssertEqual(LibraryLists.mediaLine(lib, media: .book), "1 reading")
        for m in MediaKind.allCases { XCTAssertFalse(LibraryLists.symbol(m).isEmpty) }
    }

    // MARK: 33 chips, rows

    func testChipsCountEveryStatusAndAll() throws {
        let lib = try library()
        let chips = LibraryLists.chips(lib, media: .anime)
        XCTAssertEqual(chips.map(\.label), ["All", "Watching", "Completed", "On-Hold", "Dropped", "Plan to Watch"])
        XCTAssertEqual(chips.first?.count, lib.filter { $0.media == .anime }.count)
        XCTAssertEqual(chips[1].count, 7)
        XCTAssertEqual(chips.dropFirst().reduce(0) { $0 + $1.count }, chips[0].count)
        XCTAssertEqual(LibraryLists.chips(lib, media: .manga)[1].label, "Reading")
    }

    func testRewatchingCountsUnderWatching() {
        let e = entry("A", status: .repeating)
        XCTAssertTrue(LibraryLists.keeps(.current, e))
        XCTAssertFalse(LibraryLists.keeps(.completed, e))
        XCTAssertTrue(LibraryLists.keeps(nil, e))
    }

    func testTheAnimeListStartsWithWhatYouJustWatched() throws {
        let rows = LibraryLists.shown(try library(), media: .anime, status: nil)
        XCTAssertEqual(rows.prefix(2).map(\.id), ["anime:150672", "anime:142853"], "On-Hold ones touched 15 hours ago")
        XCTAssertEqual(rows.first { $0.status == .current }?.id, "anime:210482")
        XCTAssertEqual(zip(rows, rows.dropFirst()).filter { $0.updatedAt < $1.updatedAt }.count, 0)
        XCTAssertTrue(rows.allSatisfy { $0.media == .anime })
    }

    func testSummaryLine() throws {
        let lib = try library()
        let s = LibraryLists.summary(lib, media: .anime)
        XCTAssertTrue(s.hasPrefix("\(lib.filter { $0.media == .anime }.count) entries · "), s)
        XCTAssertTrue(s.contains("days watched"), s)
        XCTAssertTrue(s.hasSuffix("mean score"), s)
        XCTAssertTrue(LibraryLists.summary(lib, media: .manga).contains("chapters read"))
        XCTAssertTrue(LibraryLists.summary(lib, media: .book).contains("pages read"))
        let two = [entry("A", progress: 10, score: 80, runtime: "24 min"), entry("B", progress: 50, score: 95, runtime: "24 min")]
        XCTAssertEqual(LibraryLists.summary(two, media: .anime), "2 entries · 1 days watched · 8.75 mean score")
        XCTAssertEqual(LibraryLists.summary([], media: .tv), "0 entries")
    }

    func testRuntimes() {
        XCTAssertEqual(LibraryLists.runtimeMinutes("24 min"), 24)
        XCTAssertEqual(LibraryLists.runtimeMinutes("2h 47m"), 167)
        XCTAssertEqual(LibraryLists.runtimeMinutes("1h"), 60)
        XCTAssertEqual(LibraryLists.runtimeMinutes("45m"), 45)
        XCTAssertNil(LibraryLists.runtimeMinutes(nil))
        XCTAssertNil(LibraryLists.runtimeMinutes("soon"))
        XCTAssertEqual(LibraryLists.minutesWatched(entry("F", media: .movie, format: nil, total: 1, status: .completed,
                                                         progress: 1, runtime: "2h")), 120)
        XCTAssertEqual(LibraryLists.minutesWatched(entry("P", media: .movie, total: 1, status: .planned)), 0)
    }

    func testRowCaptions() throws {
        let lib = try library()
        let sbr = lib.first { $0.id == "anime:210482" }!
        XCTAssertEqual(LibraryLists.caption(sbr.title), "ONA · 11 episodes")
        XCTAssertEqual(LibraryLists.progressText(sbr), "\(sbr.progress)/11")
        let op = lib.first { $0.id == "anime:21" }!
        XCTAssertEqual(LibraryLists.caption(op.title), "TV · ? episodes")
        XCTAssertEqual(LibraryLists.progressText(op), "1,150/?")
        let done = entry("D", status: .completed, progress: 12)
        XCTAssertEqual(LibraryLists.progressText(done), "12")
        let film = entry("Akira", format: "Movie", total: 1, status: .completed, progress: 1, runtime: "2h 4m")
        XCTAssertEqual(LibraryLists.formatLabel(film.title), "Film")
        XCTAssertEqual(LibraryLists.caption(film.title), "Film · 2h 4m")
        XCTAssertEqual(LibraryLists.caption(entry("M", media: .manga, format: "Manga", total: 97).title), "Manga · 97 chapters")
        XCTAssertNil(LibraryLists.progressText(entry("X", media: .movie, total: 1, status: .completed, progress: 1)))
    }

    func testWhen() {
        let now = Clock.demoNow
        XCTAssertEqual(LibraryLists.when(now.addingTimeInterval(-5 * 60), now: now), "5 min ago")
        XCTAssertEqual(LibraryLists.when(now.addingTimeInterval(-15 * 3600), now: now), "15 hours ago")
        XCTAssertEqual(LibraryLists.when(now.addingTimeInterval(-26 * 3600), now: now), "yesterday")
        XCTAssertEqual(LibraryLists.when(now.addingTimeInterval(-4 * 86_400), now: now), "4 days ago")
        XCTAssertEqual(LibraryLists.when(Format.parseDay("2026-06-29")!, now: now), "Jun 29, 2026")
    }

    func testPlusOneOnlyWhileWatchingWithMoreToGo() {
        XCTAssertTrue(LibraryLists.canStep(entry("A", progress: 4)))
        XCTAssertFalse(LibraryLists.canStep(entry("B", progress: 12)), "nothing left")
        XCTAssertTrue(LibraryLists.canStep(entry("C", total: nil, progress: 1150)), "unknown total")
        XCTAssertFalse(LibraryLists.canStep(entry("D", status: .hold, progress: 4)))
        XCTAssertFalse(LibraryLists.canStep(entry("E", media: .movie, total: 1)))
        XCTAssertEqual(LibraryLists.stepLabel(entry("A", progress: 4)), "Ep 5")
        XCTAssertEqual(LibraryLists.stepLabel(entry("M", media: .manga, total: 100, progress: 97)), "Ch 98")
        XCTAssertEqual(LibraryLists.stepLabel(entry("B", media: .book, total: 300, progress: 295)), "p. 300")
    }

    // MARK: 34 covers, 35 view mode

    func testViewModes() {
        XCTAssertEqual(LibraryViewMode.rows.other, .covers)
        XCTAssertEqual(LibraryViewMode.covers.other, .rows)
        XCTAssertEqual(LibraryViewMode(rawValue: "covers"), .covers)
        XCTAssertEqual(LibraryViewMode.allCases.map(\.label), ["Rows", "Covers"])
    }

    func testCompletedFilter() throws {
        let rows = LibraryLists.shown(try library(), media: .anime, status: .completed, sort: .score)
        XCTAssertFalse(rows.isEmpty)
        XCTAssertTrue(rows.allSatisfy { $0.status == .completed })
        XCTAssertEqual(rows.first?.score, rows.compactMap(\.score).max())
    }

    // MARK: 36 sort and format

    func testSorts() {
        let a = entry("banana", progress: 2, score: 70, daysAgo: 3)
        let b = entry("Apple", progress: 11, score: nil, daysAgo: 1)
        let c = entry("cherry", status: .completed, progress: 12, score: 90, daysAgo: 2)
        XCTAssertEqual(LibrarySort.updated.sorted([a, b, c]).map(\.title.name), ["Apple", "cherry", "banana"])
        XCTAssertEqual(LibrarySort.title.sorted([a, b, c]).map(\.title.name), ["Apple", "banana", "cherry"])
        XCTAssertEqual(LibrarySort.score.sorted([a, b, c]).map(\.title.name), ["cherry", "banana", "Apple"])
        XCTAssertEqual(LibrarySort.progress.sorted([a, b, c]).map(\.title.name), ["cherry", "Apple", "banana"])
        XCTAssertEqual(LibrarySort.allCases.map(\.label), ["Last updated", "Title", "Score", "Progress"])
    }

    func testAnimeFormats() throws {
        let lib = try library()
        let opts = LibraryFormat.options(for: .anime, in: lib)
        XCTAssertEqual(opts.map(\.label), ["All formats", "TV", "Film", "OVA · ONA · Special"])
        let film = LibraryLists.shown(lib, media: .anime, status: nil, format: opts[2])
        XCTAssertFalse(film.isEmpty)
        XCTAssertTrue(film.allSatisfy { $0.title.format == "Movie" })
        let short = LibraryLists.shown(lib, media: .anime, status: nil, format: opts[3])
        XCTAssertTrue(short.contains { $0.id == "anime:210482" })
        let all = LibraryLists.shown(lib, media: .anime, status: nil)
        let tv = LibraryLists.shown(lib, media: .anime, status: nil, format: opts[1])
        XCTAssertLessThanOrEqual(tv.count + film.count + short.count, all.count)
    }

    func testOtherMediaFormatsComeFromTheList() {
        let lib = [entry("A", media: .manga, format: "Manga"), entry("B", media: .manga, format: "Manga"),
                   entry("C", media: .manga, format: "Novel")]
        XCTAssertEqual(LibraryFormat.options(for: .manga, in: lib).map(\.label), ["All formats", "Manga", "Novel"])
        XCTAssertEqual(LibraryFormat.options(for: .book, in: [entry("D", media: .book, format: "Book")]).map(\.label),
                       ["All formats"])
    }

    func testSearch() throws {
        let lib = try library()
        XCTAssertEqual(LibraryLists.shown(lib, media: .anime, status: nil, query: "steel ball").map(\.id), ["anime:210482"])
        XCTAssertTrue(LibraryLists.search(lib, "  ").isEmpty)
        XCTAssertTrue(LibraryLists.search(lib, "frieren").contains { $0.media == .anime })
    }

    // MARK: 38-40 custom lists

    func testCustomListFixtures() throws {
        let lists = try Demo.load([CustomList].self, "api/lists.json")
        XCTAssertGreaterThanOrEqual(lists.count, 4)
        let comfort = try Demo.load(CustomList.self, "api/lists/rainy-sundays.json")
        XCTAssertEqual(comfort.name, "Rainy Sundays")
        XCTAssertEqual(comfort.countLine, "12 titles")
        XCTAssertEqual(comfort.metaLine(), "Public · 12 titles · updated yesterday")
        XCTAssertEqual(comfort.reorderLine, "12 titles · drag to reorder")
        XCTAssertEqual(comfort.covers.count, 4)
        XCTAssertGreaterThanOrEqual(comfort.items.filter { $0.note != nil }.count, 3)
        for l in lists {
            for u in l.covers {
                XCTAssertTrue(["s4.anilist.co", "image.tmdb.org", "covers.openlibrary.org"].contains(u.host ?? ""), "\(u)")
            }
        }
    }

    func testVisibilityFootnotes() {
        XCTAssertEqual(Visibility.public.listFootnote, "Anyone signed in to GupTrack can see it on your profile.")
        XCTAssertNotEqual(Visibility.friends.listFootnote, Visibility.private.listFootnote)
    }

    func testDraftNeedsAName() {
        var d = CustomListDraft()
        XCTAssertFalse(d.isValid)
        d.name = "   "
        XCTAssertFalse(d.isValid)
        d.name = " Winter evenings "
        XCTAssertTrue(d.isValid)
        XCTAssertEqual(d.trimmedName, "Winter evenings")
        XCTAssertNil(d.trimmedDescription)
        d.name = String(repeating: "x", count: 101)
        XCTAssertFalse(d.isValid)
    }

    func testDraftEditing() throws {
        let list = try Demo.load(CustomList.self, "api/lists/rainy-sundays.json")
        var d = CustomListDraft(list)
        let ids = list.items.map(\.id)
        d.move(from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(d.items.prefix(2).map(\.id), [ids[1], ids[0]])
        d.move(from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(d.items.prefix(3).map(\.id), [ids[0], ids[2], ids[1]])
        d.remove(at: IndexSet(integer: 0))
        XCTAssertEqual(d.items.count, list.items.count - 1)
        d.setNote("  A rainy-day pick ", for: ids[2])
        XCTAssertEqual(d.items.first { $0.id == ids[2] }?.note, "A rainy-day pick")
        d.setNote(" ", for: ids[2])
        XCTAssertNil(d.items.first { $0.id == ids[2] }?.note)
        d.add(list.items[1].title)
        XCTAssertEqual(d.items.filter { $0.id == ids[1] }.count, 1, "not twice")
        d.visibility = .friends
        d.description = ""
        let saved = d.applied(to: list)
        XCTAssertEqual(saved.visibility, .friends)
        XCTAssertNil(saved.description)
        XCTAssertEqual(saved.updatedAt, Clock.now)
        XCTAssertEqual(d.body.items.map(\.titleId), saved.items.map(\.id))
    }

    func testBodyIsCamelCaseJSON() throws {
        let d = CustomListDraft(name: "Winter evenings", visibility: .private,
                                items: [CustomListItem(title: Title(id: "anime:1", media: .anime, name: "X"), note: "n")])
        let json = String(decoding: try APIClient.encoder.encode(d.body), as: UTF8.self)
        XCTAssertEqual(json, #"{"description":"","items":[{"note":"n","titleId":"anime:1"}],"name":"Winter evenings","visibility":"private"}"#)
    }

    @MainActor
    func testEditsLayOverTheServersLists() throws {
        let owner = NSObject()
        let edits = CustomListEdits.shared(for: owner)
        XCTAssertTrue(CustomListEdits.shared(for: owner) === edits)
        let loaded = try Demo.load([CustomList].self, "api/lists.json")
        XCTAssertEqual(edits.merged(loaded).map(\.id), loaded.map(\.id))
        var renamed = loaded[0]
        renamed.name = "Renamed"
        edits.didSave(renamed)
        edits.didDelete(loaded[1].id)
        let id = edits.newId(for: "Winter evenings", taken: loaded.map(\.id))
        XCTAssertEqual(id, "winter-evenings")
        edits.didCreate(CustomListDraft(name: "Winter evenings").created(id: id))
        XCTAssertEqual(edits.newId(for: "Winter evenings", taken: []), "winter-evenings-2")
        let merged = edits.merged(loaded)
        XCTAssertEqual(merged.first?.id, "winter-evenings")
        XCTAssertEqual(merged[1].name, "Renamed")
        XCTAssertFalse(merged.contains { $0.id == loaded[1].id })
        XCTAssertEqual(edits.local(loaded[0].id)?.name, "Renamed")
        XCTAssertNil(edits.local(loaded[1].id))
        XCTAssertTrue(edits.isDeleted(loaded[1].id))
        XCTAssertFalse(CustomListEdits.shared(for: NSObject()) === edits, "a new session starts clean")
    }

    func testListCallsInTheDemo() async throws {
        let transport = DemoTransport()
        let api = APIClient(transport: transport, token: "t")
        let one = try await api.customList("rainy-sundays")
        XCTAssertEqual(one.items.count, 12)
        let made = try await api.createList(CustomListDraft(name: "Winter evenings").body)
        XCTAssertTrue(made.ok)
        let patched = try await api.updateList("rainy-sundays", CustomListDraft(one).body)
        XCTAssertTrue(patched.ok)
        let gone = try await api.deleteList("rainy-sundays")
        XCTAssertTrue(gone.ok)
        XCTAssertEqual(transport.requests.map { "\($0.method) \($0.path)" },
                       ["GET lists/rainy-sundays", "POST lists", "PATCH lists/rainy-sundays",
                        "DELETE lists/rainy-sundays"])
    }
}
