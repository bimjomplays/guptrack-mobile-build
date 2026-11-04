import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// Title pages (16-25), docs/app-api.md §8.3: `TitleDetail` decodes as src/catalog/detail.ts writes it, the page
/// reads it, the calls go where the doc says, and TV progress splits across seasons.
final class TitlePageTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder.decode(T.self, from: Data(json.utf8))
    }

    private func seasons(_ counts: [Int]) -> [SeasonSummary] {
        counts.enumerated().map { SeasonSummary(number: $0.offset + 1, name: "Season \($0.offset + 1)", episodes: $0.element) }
    }

    /// a TitleDetail with every field, in the doc's shape (values invented)
    static let anime = #"""
    { "title": {
      "ref": { "kind": "anime", "id": "210482" }, "media": "anime", "title": "Steel Ball Run",
      "alt": ["JoJo no Kimyou na Bouken: Steel Ball Run", "ジョジョの奇妙な冒険 スティール・ボール・ラン"],
      "cover": "https://img.example/sbr.jpg", "banner": null,
      "synopsis": [[{ "text": "A race across America. " }, { "text": "Who wins.", "spoiler": true }],
                   [{ "text": "Based on the manga by " }, { "text": "Hirohiko Araki", "ref": { "to": "person", "source": "anilist", "id": "96879" } }]],
      "format": "ONA", "status": "releasing", "statusText": "Airing", "year": 2026,
      "headline": ["ONA", "Fall 2026", "11 episodes"],
      "makers": [{ "text": "david production", "ref": { "to": "studio", "id": "287" } }],
      "facts": [{ "label": "Format", "value": "ONA" },
                { "label": "Next episode", "value": "Ep 7, Nov 6, 2026" },
                { "label": "Season", "value": "Fall 2026" },
                { "label": "Studio", "value": "david production", "links": [{ "text": "david production", "ref": { "to": "studio", "id": "287" } }] }],
      "genres": ["Action", "Adventure"], "tags": ["Horses", "action"],
      "score": 86, "scoreNote": "48,869 members", "count": 11, "minutes": 24,
      "trailer": { "youtube": "abc123" }, "idMal": 59999,
      "relations": [{ "relation": "Prequel", "title": { "ref": { "kind": "anime", "id": "190327" }, "title": "Stone Ocean", "cover": null, "format": "ONA", "year": 2021 } },
                    { "relation": "Source", "title": { "ref": { "kind": "manga", "id": "30120" }, "title": "Steel Ball Run", "cover": null, "format": "Manga", "year": 2004, "score": null } }],
      "characters": [{ "character": { "ref": { "to": "character", "id": "4004" }, "name": "Gyro Zeppeli", "image": null }, "role": "Main",
                       "voices": [{ "person": { "ref": { "to": "person", "source": "anilist", "id": "1" }, "name": "A Voice", "image": null }, "language": "English" },
                                  { "person": { "ref": { "to": "person", "source": "anilist", "id": "2" }, "name": "B Voice", "image": null }, "language": "Japanese" }] }],
      "cast": [], "staff": [{ "person": { "ref": { "to": "person", "source": "anilist", "id": "3" }, "name": "C Staff", "image": null }, "role": "Director", "note": "11 episodes" }],
      "seasons": [], "recommendations": [{ "ref": { "kind": "anime", "id": "21" }, "title": "ONE PIECE", "cover": null, "format": "TV", "year": 1999, "score": 88 }],
      "more": [{ "title": "Nothing here", "titles": [] }],
      "somethingNew": true
    } }
    """#

    func testTitleDetailDecodesAndReads() throws {
        let d = try decode(TitleAnswer.self, Self.anime).title
        let p = TitlePage(d)
        XCTAssertEqual(p.title.id, "anime:210482")
        XCTAssertEqual(p.title.score, 8.6)
        XCTAssertEqual(p.title.total, 11)
        XCTAssertEqual(p.title.runtime, "24 min")
        XCTAssertEqual(p.title.season, "Fall 2026")
        XCTAssertEqual(p.title.state, "Releasing")
        XCTAssertEqual(p.metaLine, "ONA · Fall 2026 · 11 episodes")
        XCTAssertEqual(p.creatorName, "david production")
        XCTAssertEqual(p.creatorRoute, .studio("studio:287"))
        XCTAssertEqual(p.nativeLine, "JoJo no Kimyou na Bouken: Steel Ball Run")
        XCTAssertEqual(p.averageText, "8.6")
        XCTAssertEqual(p.scoreNote, "48,869 members")
        XCTAssertEqual(p.story(), "A race across America.\n\nBased on the manga by Hirohiko Araki")
        XCTAssertEqual(p.story(spoilers: true), "A race across America. Who wins.\n\nBased on the manga by Hirohiko Araki")
        XCTAssertTrue(p.storyHasSpoilers)
        XCTAssertEqual(p.tags, ["Action", "Adventure", "Horses"], "no repeats, any case")
        XCTAssertEqual(p.nextEpisode, "Ep 7, Nov 6, 2026")
        XCTAssertEqual(p.trailer?.absoluteString, "https://www.youtube.com/watch?v=abc123")
        XCTAssertEqual(p.details[3].routes.map(\.route), [.studio("studio:287")])
        XCTAssertEqual(p.characters[0].voice?.person.name, "B Voice", "Japanese first")
        XCTAssertEqual(p.relationLabel(p.relations[0]), "Prequel")
        XCTAssertEqual(p.relationLabel(p.relations[1]), "Source · Manga")
        XCTAssertEqual(p.recommendations.first?.score, 8.8)
        XCTAssertTrue(p.more.isEmpty, "empty shelves go")
        XCTAssertEqual(p.openLinks.map(\.label), ["AniList", "MyAnimeList"])
        XCTAssertEqual(p.openLinks[1].url.absoluteString, "https://myanimelist.net/anime/59999")
    }

    func testFilmAndBookPages() throws {
        var d = try decode(TitleAnswer.self, Self.anime).title
        d.ref = TitleRef(kind: .movie, id: "693134")
        d.media = .movies
        d.minutes = 167
        d.count = 167
        let film = TitlePage(d)
        XCTAssertEqual(film.title.runtime, "2h 47m")
        XCTAssertNil(film.nativeLine)
        XCTAssertEqual(film.openLinks.map(\.url.absoluteString), ["https://www.themoviedb.org/movie/693134"])
        d.ref = TitleRef(kind: .book, id: "OL21745884W")
        d.media = .books
        d.score = 84
        let book = TitlePage(d)
        XCTAssertEqual(book.title.score, 8.4, "books are 0–100 too")
        XCTAssertNil(book.title.runtime)
        XCTAssertEqual(book.storyHeading, "About the book")
        XCTAssertEqual(book.openLinks.first?.url.absoluteString, "https://openlibrary.org/works/OL21745884W")
    }

    func testRichTextAndSeasonAnswers() throws {
        let e = try decode(SeasonAnswer.self, #"""
        { "episodes": [
          { "number": 1, "name": "Hello, Ms. Cobel", "air": "2025-01-17", "minutes": 57, "overview": "…",
            "still": "/api/app/v1/pictures/s.jpg", "score": 84 },
          { "number": 2, "name": "Goodbye", "air": null, "minutes": null, "overview": "", "still": null, "score": null } ] }
        """#)
        XCTAssertEqual(e.episodes[0].line, "Jan 17, 2025 · 57m")
        XCTAssertEqual(e.episodes[0].still?.absoluteString, "/api/app/v1/pictures/s.jpg")
        XCTAssertEqual(e.episodes[1].line, "")
        XCTAssertEqual(RichText.plain([[RichSpan(text: " x ", bold: true)], []]), "x")
    }

    func testBasicPageFromATitle() {
        let t = Title(id: "anime:9", media: .anime, name: "Nine", format: "TV", year: 2020, total: 12)
        let p = TitlePage.basic(t)
        XCTAssertEqual(p.metaLine, "TV · 2020")
        XCTAssertNil(p.story())
        XCTAssertNil(p.averageText)
        XCTAssertTrue(p.details.isEmpty)
        XCTAssertEqual(p.openLinks.map(\.label), ["AniList"])
    }

    // MARK: calls

    func testCallsGoWhereTheDocSays() async throws {
        let t = StubTransport()
        let api = APIClient(transport: t, token: "demo-token")
        t.reply(Self.anime)
        _ = try await api.titlePage("anime:210482")
        t.reply(#"{"episodes":[]}"#)
        _ = try await api.seasonEpisodes("tv:95396", 2)
        XCTAssertEqual(t.sent.map(\.path), ["titles/anime/210482", "titles/tv/95396/seasons/2"])
        XCTAssertTrue(t.sent.allSatisfy { $0.method == "GET" && $0.query.isEmpty && $0.body == nil })
        do {
            _ = try await api.seasonEpisodes("anime:1", 1)
            XCTFail("only TV has seasons")
        } catch {}
        XCTAssertEqual(t.sent.count, 2, "nothing sent for an id that can't be asked")
    }

    // MARK: Your list

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
        let tv = LibraryEntry(title: Title(id: "tv:1", media: .tv, name: "S"), status: .current, progress: 12,
                              updatedAt: Clock.demoNow)
        XCTAssertEqual(TitleListText.label(tv, seasons: seasons([9, 10])), "Your list · Season 2")
        XCTAssertEqual(TitleListText.label(tv, seasons: seasons([19])), "Your list")
    }

    func testPrimaryButton() {
        let manga = Title(id: "manga:1", media: .manga, name: "M", total: 40)
        XCTAssertEqual(TitlePrimary.of(manga, entry: nil), .markChapter(1))
        let read = LibraryEntry(title: manga, status: .current, progress: 40, updatedAt: Clock.demoNow)
        XCTAssertEqual(TitlePrimary.of(manga, entry: read), .allRead)
        XCTAssertEqual(TitlePrimary.of(Title(id: "book:OL1W", media: .book, name: "B"), entry: nil), .startReading)
        XCTAssertEqual(TitlePrimary.of(Title(id: "tv:1", media: .tv, name: "S"), entry: nil).label, "Open in Harbor")
    }

    // MARK: TV progress by season

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
        // specials (season 0) don't count
        let withSpecials = [SeasonSummary(number: 0, name: "Specials", episodes: 4)] + s
        XCTAssertEqual(TVProgress.total(withSpecials), 19)
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

    // MARK: the demo's answers

    func testDemoTitlePagesDecode() throws {
        for (kind, id) in [("anime", "210482"), ("tv", "95396"), ("movie", "693134"), ("manga", "105778"),
                           ("book", "OL21745884W"), ("anime", "20474")] {
            let d = try Demo.load(TitleAnswer.self, "api/titles/\(kind)/\(id).json").title
            XCTAssertEqual(d.ref.titleId, "\(kind):\(id)")
        }
        for n in [1, 2] {
            let s = try Demo.load(SeasonAnswer.self, "api/titles/tv/95396/seasons/\(n).json")
            XCTAssertFalse(s.episodes.isEmpty)
        }
    }

    func testEveryLibraryTitleHasAPage() throws {
        for e in Demo.library() {
            let r = try XCTUnwrap(TitleRef(titleId: e.id))
            XCTAssertNotNil(Demo.data("api/titles/\(r.kind.rawValue)/\(r.id).json"), e.id)
        }
    }
}
