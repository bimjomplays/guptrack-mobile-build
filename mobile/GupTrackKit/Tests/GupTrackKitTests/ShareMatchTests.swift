import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// Share to GupTrack (66): a shared link or text -> the title.
final class ShareMatchTests: XCTestCase {
    private func library() throws -> [LibraryEntry] { try Demo.load([LibraryEntry].self, "api/library.json") }
    private func catalog() throws -> ExtensionCatalog { try Demo.load(ExtensionCatalog.self, "api/extensions.json") }
    private func resolve(_ s: String) throws -> ShareMatch.Found? {
        ShareMatch.resolve(s, library: try library(), catalog: try catalog())
    }
    private func ref(_ s: String) -> ShareMatch.Ref? { ShareMatch.ref(URL(string: s)!) }

    func testLinksToTitleIds() {
        XCTAssertEqual(ref("https://anilist.co/anime/210482/STEEL-BALL-RUN/"), .title("anime:210482"))
        XCTAssertEqual(ref("https://anilist.co/manga/105778"), .title("manga:105778"))
        XCTAssertEqual(ref("https://www.themoviedb.org/tv/95396-severance"), .title("tv:95396"))
        XCTAssertEqual(ref("https://www.themoviedb.org/movie/693134-dune-part-two?language=en-US"), .title("movie:693134"))
        XCTAssertEqual(ref("https://openlibrary.org/works/OL21745884W/Project_Hail_Mary"), .title("book:OL21745884W"))
        XCTAssertEqual(ref("https://myanimelist.net/anime/61469/JoJo"), .mal("anime/61469"))
        XCTAssertEqual(ref("guptrack://title/anime:210482"), .title("anime:210482"))
        XCTAssertEqual(ref("https://letterboxd.com/film/dune-part-two/"), .words("dune part two"))
        XCTAssertEqual(ref("https://openlibrary.org/books/OL1234M/The_Martian"), .words("the martian"))
        XCTAssertNil(ref("https://www.themoviedb.org/"))
        XCTAssertNil(ref("guptrack://settings"))
    }

    func testLinkLabel() {
        XCTAssertEqual(ShareMatch.label(URL(string: "https://www.themoviedb.org/tv/95396-severance/")!),
                       "themoviedb.org/tv/95396-severance")
        XCTAssertEqual(ShareMatch.label(URL(string: "https://anilist.co/anime/1?x=1")!), "anilist.co/anime/1")
    }

    func testFirstURLInText() {
        XCTAssertEqual(ShareMatch.firstURL(in: "watch this https://anilist.co/anime/21. so good")?.absoluteString,
                       "https://anilist.co/anime/21")
        XCTAssertNil(ShareMatch.firstURL(in: "no link here"))
    }

    func testATMDBLinkMatchesTheShowOnYourList() throws {
        let f = try XCTUnwrap(try resolve("https://www.themoviedb.org/tv/95396-severance"))
        XCTAssertEqual(f.title.id, "tv:95396")
        XCTAssertEqual(f.how, .link)
        XCTAssertEqual(f.link, "themoviedb.org/tv/95396-severance")
        XCTAssertEqual(f.entry?.status, .current)
        XCTAssertEqual(ShareMatch.addLabel(f), "Save")
        XCTAssertEqual(ShareMatch.caption(f.title, seasons: [9, 10]), "TV · 2022 · 2 seasons")
    }

    func testAMALLinkGoesThroughTheCatalogue() throws {
        let f = try XCTUnwrap(try resolve("https://myanimelist.net/anime/61469/JoJo_no_Kimyou_na_Bouken"))
        XCTAssertEqual(f.title.id, "anime:210482")
        XCTAssertEqual(f.how, .link)
    }

    func testATitleNotOnTheListIsNew() throws {
        let extra = try XCTUnwrap(try catalog().titles.first { $0.media == .anime })
        let num = extra.id.split(separator: ":")[1]
        let f = try XCTUnwrap(try resolve("https://anilist.co/anime/\(num)"))
        XCTAssertEqual(f.title.id, extra.id)
        XCTAssertNil(f.entry)
        XCTAssertEqual(ShareMatch.addLabel(f), "Add to Anime")
        XCTAssertEqual(ShareMatch.Draft(f), ShareMatch.Draft(status: .planned, progress: 0))
    }

    func testTextFindsTheTitleByName() throws {
        let f = try XCTUnwrap(try resolve("Severance | Apple TV+"))
        XCTAssertEqual(f.title.id, "tv:95396")
        XCTAssertEqual(f.how, .search)
        XCTAssertNil(f.link)
        let slug = try XCTUnwrap(try resolve("https://letterboxd.com/film/dune-part-two/"))
        XCTAssertEqual(slug.title.id, "movie:693134")
        XCTAssertEqual(slug.how, .search)
        XCTAssertEqual(slug.link, "letterboxd.com/film/dune-part-two")
        XCTAssertNil(try resolve("zzqx nothing like this"))
        XCTAssertNil(try resolve("   "))
    }

    func testSearchPrefersTheWholeName() {
        let a = Title(id: "anime:1", media: .anime, name: "Dune Watchers")
        let b = Title(id: "book:OL1W", media: .book, name: "Dune")
        XCTAssertEqual(ShareMatch.search("dune", in: [a, b])?.id, "book:OL1W")
        XCTAssertEqual(ShareMatch.search("Dune: watchers", in: [a, b])?.id, "anime:1")
        XCTAssertEqual(ShareMatch.words("Frieren: Beyond Journey’s End"), "frieren beyond journeys end")
    }

    func testStepperShowsTheSeason() throws {
        let sev = try XCTUnwrap(try library().first { $0.id == "tv:95396" })
        let s = try XCTUnwrap(ShareMatch.stepper(sev.title, progress: 15, seasons: [9, 10]))
        XCTAssertEqual(s, ShareMatch.Stepper(value: 6, total: 10, note: "Season 2", max: 19))
        let film = Title(id: "movie:1", media: .movie, name: "A Film")
        XCTAssertNil(ShareMatch.stepper(film, progress: 0, seasons: nil))
        let anime = Title(id: "anime:1", media: .anime, name: "A Show", total: 12)
        XCTAssertEqual(ShareMatch.stepper(anime, progress: 3, seasons: nil)?.total, 12)
    }

    func testDraftPatch() {
        let d = ShareMatch.Draft(status: .current, progress: 5)
        XCTAssertEqual(d.patch, LibraryPatch(status: .current, progress: 5))
        XCTAssertEqual(ShareMatch.statuses, [.planned, .current, .completed, .hold, .dropped])
        var e = ShareMatch.Draft(status: .planned, progress: 0)
        e.step(1, media: .tv, max: 19)
        XCTAssertEqual(e, ShareMatch.Draft(status: .current, progress: 1), "a step starts a planned title")
        e.step(-5, media: .tv, max: 19)
        XCTAssertEqual(e.progress, 0)
        e.step(1, media: .book, max: 5)
        XCTAssertEqual(e.progress, 5, "books go by 10 pages, up to the end")
        e.choose(.completed, max: 19)
        XCTAssertEqual(e, ShareMatch.Draft(status: .completed, progress: 19))
        e.choose(.hold, max: nil)
        XCTAssertEqual(e.status, .hold)
    }

    func testOutboxKeepsShareAddsApart() throws {
        let d = try XCTUnwrap(UserDefaults(suiteName: "share-tests-\(UUID().uuidString)"))
        var box = WidgetOutbox()
        box.changes.append(.init(id: "tv:95396", patch: LibraryPatch(status: .current), at: Date(timeIntervalSince1970: 0)))
        box.save(d, key: "share-outbox")
        XCTAssertEqual(WidgetOutbox.load(d, key: "share-outbox"), box)
        XCTAssertEqual(WidgetOutbox.load(d), WidgetOutbox())
        XCTAssertNil(ExtensionsJSON.bundled(ExtensionCatalog.self, "no-such-file"))
    }
}
