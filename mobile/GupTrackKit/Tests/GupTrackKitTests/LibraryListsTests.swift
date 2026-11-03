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

    private func library() throws -> [LibraryEntry] { Demo.library() }

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

    func testAllIsGroupedByStatusLikeTheWebsite() throws {
        let rows = LibraryLists.shown(try library(), media: .anime, status: nil)
        XCTAssertEqual(rows.first?.id, "anime:210482", "Watching comes first, though On-Hold ones were touched later")
        let groups = rows.map { ListStatus.ordered.firstIndex(of: $0.status.isActive ? .current : $0.status) ?? 0 }
        XCTAssertEqual(groups, groups.sorted(), "Watching, Completed, On-Hold, Dropped, Plan to Watch")
        for (a, b) in zip(rows, rows.dropFirst()) where a.status == b.status {
            XCTAssertGreaterThanOrEqual(a.updatedAt, b.updatedAt, "last updated first within a status")
        }
        XCTAssertTrue(rows.allSatisfy { $0.media == .anime })
        // another sort keeps the groups, sorted inside each
        let byTitle = LibraryLists.shown(try library(), media: .anime, status: nil, sort: .title)
        XCTAssertEqual(byTitle.first?.status, .current)
        for (a, b) in zip(byTitle, byTitle.dropFirst()) where a.status == b.status {
            XCTAssertNotEqual(a.title.name.localizedCaseInsensitiveCompare(b.title.name), .orderedDescending)
        }
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

    private func myList(_ slug: String) throws -> MyList { try Demo.load(MyList.self, "api/lists/\(slug).json") }

    func testCustomListFixtures() throws {
        let yours = try Demo.load(ListWire.Yours.self, "api/lists.json")
        XCTAssertEqual(yours.profile, .public)
        XCTAssertEqual(yours.lists.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(yours.lists.map(\.slug), ["rainy-sundays", "this-years-highlights", "shonen-marathon", "start-here"])
        let rainy = try myList("rainy-sundays")
        XCTAssertEqual(rainy.count, rainy.items.count)
        let comfort = rainy.customList()
        XCTAssertEqual(comfort.id, "1")
        XCTAssertEqual(comfort.serverId, 1)
        XCTAssertEqual(comfort.name, "Rainy Sundays")
        XCTAssertEqual(comfort.countLine, "12 titles")
        XCTAssertEqual(comfort.metaLine(), "Public · 12 titles · updated yesterday")
        XCTAssertEqual(comfort.reorderLine, "12 titles · drag to reorder")
        XCTAssertEqual(comfort.covers.count, 4)
        XCTAssertGreaterThanOrEqual(comfort.items.filter { $0.note != nil }.count, 3)
        XCTAssertEqual(try myList("shonen-marathon").customList().visibility, .friends, "the list's own setting")
        for s in yours.lists {
            let l = try myList(s.slug)
            XCTAssertEqual(l.id, s.id)
            for u in l.customList().covers {
                XCTAssertTrue(["s4.anilist.co", "image.tmdb.org", "covers.openlibrary.org"].contains(u.host ?? ""), "\(u)")
            }
        }
    }

    func testMyListDecodesTheDocShape() throws {
        let json = #"""
        {"id":9,"slug":"cozy","name":"Cozy","description":"","count":1,"covers":[null],"media":["books"],"updated":1793700000000,
         "level":{"list":"private","profile":"friends"},"future":true,
         "items":[{"media":"books","id":"OL1W","title":"A Book","cover":null,"format":"","year":null,"note":"","added":1,"mine":null}]}
        """#
        let l = try APIClient.decoder.decode(MyList.self, from: Data(json.utf8)).customList()
        XCTAssertEqual(l.id, "9")
        XCTAssertNil(l.description)
        XCTAssertEqual(l.visibility, .private)
        XCTAssertEqual(l.items.map(\.id), ["book:OL1W"])
        XCTAssertNil(l.items[0].note)
        XCTAssertNil(l.items[0].title.format)
        XCTAssertEqual(l.updatedAt, Millis.date(1_793_700_000_000))
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
        d.name = String(repeating: "x", count: 80)
        XCTAssertTrue(d.isValid)
        d.name = String(repeating: "x", count: 81)
        XCTAssertFalse(d.isValid)
        d.name = "Ok"
        d.description = String(repeating: "y", count: 501)
        XCTAssertFalse(d.isValid)
    }

    func testDraftEditing() throws {
        let list = try myList("rainy-sundays").customList()
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
        d.setNote(String(repeating: "n", count: 300), for: ids[2])
        XCTAssertEqual(d.items.first { $0.id == ids[2] }?.note?.count, 280)
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
    }

    func testNewListBody() throws {
        let d = CustomListDraft(name: " Winter evenings ", visibility: .private)
        let t = Title(id: "movie:603", media: .movie, name: "The Matrix",
                      cover: URL(string: "https://image.tmdb.org/t/p/w500/a.jpg"), format: "Film", year: 1999)
        let json = String(decoding: try APIClient.encoder.encode(d.newList(item: t)), as: UTF8.self)
        XCTAssertEqual(json, #"{"description":"","item":{"cover":"https:\/\/image.tmdb.org\/t\/p\/w500\/a.jpg","format":"Film","id":"603","media":"movies","title":"The Matrix","year":1999},"name":"Winter evenings","visibility":"private"}"#)
        XCTAssertEqual(String(decoding: try APIClient.encoder.encode(d.newList()), as: UTF8.self),
                       #"{"description":"","name":"Winter evenings","visibility":"private"}"#)
        let s = try Demo.load(ListWire.Summary.self, "api/lists.post.json")
        let made = d.created(s, item: t)
        XCTAssertEqual(made.id, String(s.id))
        XCTAssertEqual(made.items.map(\.id), ["movie:603"])
    }

    func testSavingSendsOnlyWhatChanged() throws {
        let list = try myList("start-here").customList()
        XCTAssertTrue(CustomListDraft(list).calls(from: list).isEmpty, "nothing changed, nothing sent")
        let ids = list.items.map(\.id)
        var d = CustomListDraft(list)
        d.name = "Start here first"
        d.visibility = .friends
        d.remove(at: IndexSet(integer: 0))
        d.add(Title(id: "anime:21", media: .anime, name: "One Piece", format: "TV", year: 1999))
        d.setNote("Begin with this one", for: ids[2])
        d.move(from: IndexSet(integer: 3), to: 0)
        let calls = d.calls(from: list)
        let refs = d.items.compactMap { ListWire.Ref(titleId: $0.id) }
        XCTAssertEqual(calls, [
            .change(.init(name: "Start here first", visibility: .friends)),
            .takeOff(try XCTUnwrap(ListWire.Ref(titleId: ids[0]))),
            .add(.init(media: .anime, id: "21", title: "One Piece", cover: nil, format: "TV", year: 1999)),
            .note(try XCTUnwrap(ListWire.Ref(titleId: ids[2])), "Begin with this one"),
            .order(refs),
        ])
        XCTAssertEqual(refs.first?.id, "21")
        var plain = CustomListDraft(list)
        plain.remove(at: IndexSet(integer: 1))
        XCTAssertEqual(plain.calls(from: list).count, 1, "taking one off keeps the order: no order call")
    }

    @MainActor
    func testEditsLayOverTheFeedsLists() throws {
        let owner = NSObject()
        let edits = CustomListEdits.shared(for: owner)
        XCTAssertTrue(CustomListEdits.shared(for: owner) === edits)
        let feed = try ["rainy-sundays", "this-years-highlights", "shonen-marathon"].map(myList)
        XCTAssertEqual(edits.merged(feed).map(\.id), ["1", "2", "3"])
        var renamed = feed[0].customList()
        renamed.name = "Renamed"
        edits.didSave(renamed, over: feed[0].updated)
        edits.didDelete("2")
        let s = try Demo.load(ListWire.Summary.self, "api/lists.post.json")
        edits.didCreate(CustomListDraft(name: "Winter evenings").created(s))
        var merged = edits.merged(feed)
        XCTAssertEqual(merged.map(\.id), ["5", "1", "3"], "new first, deleted hidden")
        XCTAssertEqual(merged[1].name, "Renamed")
        XCTAssertTrue(edits.isDeleted("2"))
        var newer = feed
        newer[0].updated += 1
        newer[0].name = "From the server"
        merged = edits.merged(newer)
        XCTAssertEqual(merged[1].name, "From the server", "the feed's newer copy wins")
        XCTAssertFalse(CustomListEdits.shared(for: NSObject()) === edits, "a new session starts clean")
    }

    func testListCallsInTheDemo() async throws {
        let transport = DemoTransport()
        let api = APIClient(transport: transport, token: "demo-token")
        let one = try await api.myList(id: 1)
        XCTAssertEqual(one.items.count, 12)
        let all = try await api.customLists()
        XCTAssertEqual(all.map(\.id), ["1", "2", "3", "4"])
        let made = try await api.createList(CustomListDraft(name: "Winter evenings").newList())
        XCTAssertEqual(made.id, 5)
        let renamed = try await api.updateList(1, .init(name: "Rainy Sundays"))
        XCTAssertEqual(renamed.slug, "rainy-sundays")
        let ref = ListWire.Ref(media: .anime, id: "1575")
        try await api.run(.note(ref, "x"), on: 1)
        try await api.run(.order([ref]), on: 1)
        _ = try await api.orderLists([2, 1])
        let gone = try await api.deleteList(1)
        XCTAssertTrue(gone.ok)
        let writes = transport.requests.filter { $0.method != "GET" }
        XCTAssertEqual(writes.map { "\($0.method) \($0.path)" },
                       ["POST lists", "PATCH lists/1", "POST lists/1/items/note", "POST lists/1/items/order",
                        "POST lists/order", "DELETE lists/1"])
        XCTAssertEqual(writes.map { $0.body.map { String(decoding: $0, as: UTF8.self) } ?? "-" },
                       [#"{"description":"","name":"Winter evenings","visibility":"public"}"#,
                        #"{"name":"Rainy Sundays"}"#,
                        #"{"note":"x","ref":{"id":"1575","media":"anime"}}"#,
                        #"{"refs":[{"id":"1575","media":"anime"}]}"#,
                        #"{"ids":[2,1]}"#, "-"])
        XCTAssertEqual(transport.requests.prefix(2).map(\.path), ["lists", "lists/rainy-sundays"])
    }
}
