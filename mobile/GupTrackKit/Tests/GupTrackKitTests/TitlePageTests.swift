import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// Title pages (16-25): the fixtures decode, and the page's words and TV progress come out right.
final class TitlePageTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func page(_ id: String) throws -> TitlePage { try Demo.load(TitlePage.self, Demo.file("titles/" + id)) }

    private func entry(_ id: String) throws -> LibraryEntry {
        let lib = try Demo.load([LibraryEntry].self, "api/library.json")
        return try XCTUnwrap(lib.first { $0.id == id })
    }

    private func seasons(_ counts: [Int]) -> [TVSeason] {
        counts.enumerated().map { TVSeason(number: $0.offset + 1, name: "Season \($0.offset + 1)", count: $0.element) }
    }

    func testEveryTitlePageDecodes() throws {
        let dir = Demo.root.appendingPathComponent("api/titles")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") }
        XCTAssertGreaterThan(files.count, 100)
        for f in files {
            let p = try Demo.load(TitlePage.self, "api/titles/" + f)
            XCTAssertEqual(Demo.safe(p.title.id) + ".json", f)
        }
    }

    func testEveryLibraryTitleHasAPage() throws {
        let lib = try Demo.load([LibraryEntry].self, "api/library.json")
        for e in lib { XCTAssertNoThrow(try page(e.id), e.id) }
    }

    func testSeasonPagesDecode() throws {
        for n in [1, 2] {
            let s = try Demo.load(TVSeasonPage.self, Demo.file("titles/tv:95396/seasons/\(n)"))
            XCTAssertEqual(s.season.number, n)
            XCTAssertEqual(s.season.episodes?.count, s.season.count)
            XCTAssertEqual(s.seasons.map(\.count), [9, 10])
        }
    }

    func testAnimePage() throws {
        let p = try page("anime:210482")
        XCTAssertEqual(p.metaLine.hasPrefix(p.title.format ?? "?"), true)
        XCTAssertTrue(p.metaLine.contains("episodes"))
        XCTAssertEqual(p.creatorName, "david production")
        XCTAssertEqual(p.creator?.route, .studio("studio:287"))
        XCTAssertNotNil(p.nativeLine)
        XCTAssertEqual(p.characters?.count, 10)
        XCTAssertEqual(p.characters?.first?.route, .character("character:11772"))
        XCTAssertEqual(p.characters?.first?.voice?.route, .person("person:109155"))
        XCTAssertEqual(p.relations.map { $0.map(p.relationLabel) }, ["Prequel", "Source · Manga"])
        XCTAssertEqual(p.membersLine, "48,869 members")
        XCTAssertEqual(p.scoreHeights.last?.height, 1)
        XCTAssertTrue(p.hasScoreAverage)
        XCTAssertEqual(p.runLine, "Sep 25, 2026 – ongoing")
        XCTAssertEqual(p.openLinks.map(\.label), ["AniList", "MyAnimeList"])
        XCTAssertEqual(p.details.first { $0.label == "Studio" }?.ref, "studio:287")
        XCTAssertEqual(TitlePrimary.of(p.title, entry: nil), .harbor)
    }

    func testTVPage() throws {
        let p = try page("tv:95396")
        XCTAssertEqual(p.metaLine, "Series · 2022 · 2 seasons")
        XCTAssertEqual(p.creatorName, "Dan Erickson")
        XCTAssertEqual(p.seasons?.map(\.count), [9, 10])
        let e = try entry("tv:95396")
        let pos = try XCTUnwrap(TVProgress.position(e.progress, p.seasons ?? []))
        XCTAssertEqual(TitleListText.label(e, seasons: p.seasons), "Your list · Season \(pos.season)")
    }

    func testFilmPage() throws {
        let p = try page("movie:693134")
        XCTAssertEqual(p.metaLine, "Film · 2024 · 2h 47m")
        XCTAssertEqual(p.creatorName, "Denis Villeneuve")
        XCTAssertEqual(p.tagline, "Long live the fighters.")
        XCTAssertNotNil(p.trailer)
        XCTAssertEqual(p.cast?.first?.route, .person("person:tmdb-1190668"))
        XCTAssertNil(p.cast?.last?.route)
        XCTAssertEqual(p.details.map(\.label), ["Released", "Runtime", "Genres"])
        XCTAssertEqual(p.details.first?.value, "Mar 1, 2024")
    }

    func testMangaPage() throws {
        let p = try page("manga:105778")
        XCTAssertTrue(p.metaLine.hasPrefix("Manga · 2018 · "))
        XCTAssertTrue(p.metaLine.contains(" ch"))
        XCTAssertEqual(p.nativeLine?.contains("チェンソーマン"), true)
        XCTAssertEqual(p.staff?.first?.role, "Story & Art")
        XCTAssertEqual(p.staff?.first?.route, .person("person:119917"))
        let e = try entry("manga:105778")
        XCTAssertEqual(TitlePrimary.of(p.title, entry: e), .markChapter(e.progress + 1))
        XCTAssertEqual(TitlePrimary.markChapter(98).label, "Mark Ch 98 read")
        XCTAssertNil(p.openLinks.first { $0.label == "Harbor" })
    }

    func testBookPage() throws {
        let p = try page("book:OL21745884W")
        XCTAssertEqual(p.metaLine, "Novel · 2021 · 496 pages")
        XCTAssertEqual(p.creatorName, "Andy Weir")
        XCTAssertEqual(p.creator?.route, .author("author:OL7234434A"))
        XCTAssertEqual(p.averageText, "4.5")
        XCTAssertEqual(p.averageOutOf, "/ 5")
        XCTAssertEqual(p.storyHeading, "About the book")
        XCTAssertNil(p.nativeLine)
        XCTAssertEqual(p.tags, ["Hard science fiction", "Science fiction", "NYT bestseller"])
        let e = try entry("book:OL21745884W")
        XCTAssertEqual(TitlePrimary.of(p.title, entry: e), .updateProgress)
        XCTAssertEqual(TitlePrimary.of(p.title, entry: nil), .startReading)
        XCTAssertEqual(TitleListText.caption(e), "Page \(e.progress) of 496 · + and − move 10 pages")
    }

    func testSubjectTags() {
        XCTAssertEqual(TitlePage.subjectTags(["hard science-fiction", "sci-fi", "Science fiction", "nyt:x=1",
                                             "New York Times reviewed", "Fiction, general", "space"]),
                       ["Hard science fiction", "Science fiction", "Space"])
    }

    func testCaptions() throws {
        let t = Title(id: "movie:1", media: .movie, name: "A film")
        var e = LibraryEntry(title: t, status: .completed, score: 70, repeats: 1, finished: "2025-04-02",
                             updatedAt: Clock.demoNow)
        XCTAssertEqual(TitleListText.caption(e), "Watched Apr 2, 2025 · seen twice")
        XCTAssertEqual(TitleListText.history(e), "★ 7 · 2 watches")
        e.repeats = 2
        XCTAssertEqual(TitleListText.caption(e), "Watched Apr 2, 2025 · seen 3 times")
        let m = LibraryEntry(title: Title(id: "manga:1", media: .manga, name: "M"), status: .current, progress: 40,
                             volume: 6, updatedAt: Clock.demoNow)
        XCTAssertEqual(TitleListText.caption(m), "Chapter 40 · Volume 6")
    }

    func testRoutes() {
        XCTAssertEqual(TitlePage.route(for: "person:tmdb-1"), .person("person:tmdb-1"))
        XCTAssertEqual(TitlePage.route(for: "studio:tmdb-49"), .studio("studio:tmdb-49"))
        XCTAssertEqual(TitlePage.route(for: "author:OL1A"), .author("author:OL1A"))
        XCTAssertEqual(TitlePage.route(for: "character:5"), .character("character:5"))
        XCTAssertNil(TitlePage.route(for: "person:"))
        XCTAssertNil(TitlePage.route(for: "anime:5"))
    }

    func testBasicPageFromATitle() {
        let t = Title(id: "anime:9", media: .anime, name: "Nine", format: "TV", year: 2020, total: 12)
        let p = TitlePage.basic(t)
        XCTAssertEqual(p.metaLine, "TV · 2020 · 12 episodes")
        XCTAssertNil(p.story)
        XCTAssertFalse(p.hasScoreAverage)
        XCTAssertEqual(p.details.map(\.label), ["Format", "Episodes"])
    }

    func testTVPosition() {
        let s = seasons([9, 10])
        XCTAssertEqual(TVProgress.position(0, s), TVProgress(season: 1, watched: 0, count: 9))
        XCTAssertEqual(TVProgress.position(12, s), TVProgress(season: 2, watched: 3, count: 10))
        XCTAssertEqual(TVProgress.position(12, s)?.next, 4)
        XCTAssertEqual(TVProgress.position(19, s), TVProgress(season: 2, watched: 10, count: 10))
        XCTAssertNil(TVProgress.position(19, s)?.next)
        XCTAssertNil(TVProgress.position(3, []))
        XCTAssertEqual(TVProgress.watched(in: s[0], progress: 12, s), 9)
        XCTAssertEqual(TVProgress.watched(in: s[1], progress: 12, s), 3)
    }

    func testTVMarking() {
        let s = seasons([9, 10])
        XCTAssertEqual(TVProgress.mark(episode: 5, season: 2, progress: 12, s), LibraryPatch(progress: 14, season: 2))
        XCTAssertEqual(TVProgress.mark(episode: 2, season: 2, progress: 12, s), LibraryPatch(progress: 10, season: 2))
        XCTAssertEqual(TVProgress.mark(episode: 1, season: 2, progress: 12, s), LibraryPatch(progress: 9, season: 2))
        XCTAssertEqual(TVProgress.markAll(season: 1, s), LibraryPatch(progress: 9, season: 2))
        XCTAssertEqual(TVProgress.markAll(season: 2, s), LibraryPatch(status: .completed, progress: 19, season: 2))
        XCTAssertEqual(TVProgress.step(12, by: 1, s), LibraryPatch(progress: 13, season: 2))
        XCTAssertEqual(TVProgress.step(0, by: -1, s), LibraryPatch(progress: 0, season: 1))
        XCTAssertEqual(TVProgress.step(19, by: 1, s).progress, 19)
    }

    func testAiringSplit() {
        let a = Airing(episode: 7, at: Clock.demoNow.addingTimeInterval(3 * 86400))
        let (head, rest) = TitleListText.airing(a, media: .anime)
        XCTAssertEqual(head, "Ep 7")
        XCTAssertTrue(rest.hasPrefix(" · "))
    }
}
