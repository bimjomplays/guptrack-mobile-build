import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// Profiles and statistics (41-43b, 48, 49): the maths from the library, the captions, and the fixtures.
final class ProfileTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func library() throws -> [LibraryEntry] { try Demo.load([LibraryEntry].self, "api/library.json") }

    private func entry(_ id: String, _ status: ListStatus, progress: Int = 0, total: Int? = 12, score: Int? = nil,
                       repeats: Int = 0, media: MediaKind = .anime, format: String? = "TV", runtime: String? = nil,
                       year: Int? = nil, genres: [String]? = nil, studio: String? = nil) -> LibraryEntry {
        let t = Title(id: id, media: media, name: id, format: format, year: year, total: total, genres: genres,
                      studio: studio, runtime: runtime)
        return LibraryEntry(title: t, status: status, progress: progress, score: score, repeats: repeats,
                            updatedAt: Clock.demoNow)
    }

    // MARK: statistics

    func testCountsMeanAndTime() {
        let lib = [
            entry("anime:1", .completed, progress: 12, score: 80, runtime: "24 min"),
            entry("anime:2", .current, progress: 6, score: 90, runtime: "24 min"),
            entry("anime:3", .planned, progress: 0),
            entry("anime:4", .completed, progress: 1, total: 1, score: 100, repeats: 1, format: "Movie", runtime: "2h"),
            entry("anime:5", .repeating, progress: 3, total: 10, repeats: 1, runtime: "20 min"),
            entry("manga:1", .completed, progress: 100, score: 50, media: .manga, format: "Manga"),
        ]
        let s = LibraryStats(lib, media: .anime)
        XCTAssertEqual(s.summary.entries, 5)
        XCTAssertEqual(s.summary.count(.completed), 2)
        XCTAssertEqual(s.summary.count(.current), 2, "rewatching counts as watching")
        XCTAssertEqual(s.summary.count(.planned), 1)
        XCTAssertEqual(s.summary.scored, 3)
        XCTAssertEqual(s.summary.meanText, "9.00")
        XCTAssertEqual(s.summary.rewatched, 2)
        // 12 + 6 + 0 + (1 + 1 film twice) + (3 + 1×10)
        XCTAssertEqual(s.summary.units, 12 + 6 + 2 + 13)
        XCTAssertEqual(s.summary.minutes, 18 * 24 + 2 * 120 + 13 * 20)
        XCTAssertEqual(s.summary.percent(.completed), "40%")
        XCTAssertEqual(s.perfect, 1)
        XCTAssertEqual(s.medianText, "9")
        XCTAssertEqual(s.histogram, [0, 0, 0, 0, 0, 0, 0, 1, 1, 1])
        XCTAssertEqual(s.formats.first { $0.label == "Film" }?.count, 1, "an anime film is a Film, under Anime")
        XCTAssertFalse(s.formats.contains { $0.label == "Movie" })
    }

    func testColumnsPerMedia() {
        var s = LibraryStats.Summary(media: .anime)
        s.minutes = 30_000
        s.mean = 7.5
        s.units = 1234
        XCTAssertEqual(s.columns.map(\.value), ["20.8", "7.50", "0", "1,234"])
        XCTAssertEqual(s.columns.map(\.label), ["Days", "Mean score", "Rewatched", "Episodes"])
        XCTAssertEqual(s.timeHeadline.main, "20 days")
        XCTAssertEqual(s.timeHeadline.rest, "20 hours")
        XCTAssertEqual(LibraryStats.Summary(media: .manga).columns.map(\.label), ["Chapters", "Mean score", "Reread", "Completed"])
        XCTAssertEqual(LibraryStats.Summary(media: .book).columns.map(\.label), ["Pages", "Mean score", "Reread", "Books read"])
        XCTAssertEqual(LibraryStats.Summary(media: .movie).columns.last?.label, "Films")
        XCTAssertEqual(LibraryStats.Summary(media: .anime).meanText, "–")
        XCTAssertEqual(LibraryStats.Summary(media: .manga).timeLabel, "Chapters read")
    }

    func testTimeLine() {
        var s = LibraryStats.Summary(media: .anime)
        s.entries = 150
        s.units = 1234
        s.counts = ["planned": 60, "completed": 80, "current": 10]
        XCTAssertEqual(s.timeLine, "1,234 episodes · 150 entries · 90 watched or watching")
        var b = LibraryStats.Summary(media: .book)
        b.entries = 1
        XCTAssertEqual(b.timeLine, "1 entry · 1 read or reading")
    }

    func testRuntimes() {
        XCTAssertEqual(LibraryStats.parseRuntime("24 min"), 24)
        XCTAssertEqual(LibraryStats.parseRuntime("2h 47m"), 167)
        XCTAssertEqual(LibraryStats.parseRuntime("1h"), 60)
        XCTAssertEqual(LibraryStats.parseRuntime("90"), 90)
        XCTAssertNil(LibraryStats.parseRuntime("unknown"))
        XCTAssertEqual(LibraryStats.minutes(Title(id: "tv:1", media: .tv, name: "x")), 45)
    }

    func testHistogramBuckets() {
        XCTAssertEqual(LibraryStats.bucket(85), 9)
        XCTAssertEqual(LibraryStats.bucket(80), 8)
        XCTAssertEqual(LibraryStats.bucket(5), 1)
        XCTAssertEqual(LibraryStats.bucket(100), 10)
    }

    func testYearBuckets() {
        let y = LibraryStats.yearBuckets([1998, 2003, 2011, 2026, 2024])
        XCTAssertEqual(y.map(\.label), ["’95", "’00", "’05", "’10", "’15", "’20", "’25"])
        XCTAssertEqual(y.map(\.count), [1, 1, 0, 1, 0, 1, 1])
        let wide = LibraryStats.yearBuckets([1965, 2021])
        XCTAssertEqual(wide.first?.label, "’60")
        XCTAssertEqual(wide.count, 7, "10-year steps when 5-year ones would be too many")
        XCTAssertTrue(LibraryStats.yearBuckets([]).isEmpty)
    }

    func testGenresAndStudiosLeavePlannedOut() {
        let lib = [
            entry("anime:1", .completed, score: 80, genres: ["Action", "Drama"], studio: "MAPPA"),
            entry("anime:2", .completed, score: 90, genres: ["Action"], studio: "MAPPA"),
            entry("anime:3", .planned, genres: ["Action", "Comedy"], studio: "bones"),
        ]
        let s = LibraryStats(lib, media: .anime)
        XCTAssertEqual(s.genres.map(\.name), ["Action", "Drama"])
        XCTAssertEqual(s.genres.first?.count, 2)
        XCTAssertEqual(s.genres.first?.meanText, "8.5")
        XCTAssertEqual(s.studios.map(\.name), ["MAPPA"])
    }

    func testDemoLibraryStats() throws {
        let lib = try library()
        for m in MediaKind.allCases {
            let s = LibraryStats(lib, media: m)
            XCTAssertEqual(s.summary.entries, lib.filter { $0.media == m }.count)
            XCTAssertEqual(ListStatus.ordered.reduce(0) { $0 + s.summary.count($1) }, s.summary.entries)
            XCTAssertEqual(s.histogram.reduce(0, +), s.summary.scored)
            XCTAssertEqual(s.formats.reduce(0) { $0 + $1.count }, s.summary.entries)
        }
        let anime = LibraryStats(lib, media: .anime)
        XCTAssertGreaterThan(anime.summary.minutes, 0)
        XCTAssertFalse(anime.genres.isEmpty)
        XCTAssertFalse(anime.studios.isEmpty)
        XCTAssertFalse(anime.years.isEmpty)
    }

    // MARK: captions

    func testUpdateCaptions() {
        XCTAssertEqual(ProfileText.updateCaption(entry("a:1", .current, progress: 6, total: 11)), "Ep 6 of 11")
        XCTAssertEqual(ProfileText.updateCaption(entry("a:1", .current, progress: 0)), "Started")
        XCTAssertEqual(ProfileText.updateCaption(entry("a:1", .completed, progress: 12, score: 90)), "Completed · ★9")
        XCTAssertEqual(ProfileText.updateCaption(entry("a:1", .repeating, progress: 12, total: 26)), "Rewatching · Ep 12")
        XCTAssertEqual(ProfileText.updateCaption(entry("a:1", .planned)), "Plan to Watch")
        XCTAssertEqual(ProfileText.updateCaption(entry("m:1", .current, progress: 97, total: nil, media: .manga)), "Ch 97")
        XCTAssertEqual(ProfileText.count(1, "friend"), "1 friend")
        XCTAssertEqual(ProfileText.count(1204, "friend"), "1,204 friends")
    }

    func testLastUpdatesNewestFirst() throws {
        let ups = ProfileText.lastUpdates(try library(), limit: 5)
        XCTAssertEqual(ups.count, 5)
        XCTAssertEqual(ups.map(\.at), ups.map(\.at).sorted(by: >))
    }

    // MARK: compare

    func testCompareMaths() {
        func row(_ id: String, _ a: Int?, _ b: Int?) -> CompareResult.Row {
            CompareResult.Row(title: Title(id: id, media: .anime, name: id), mine: a, theirs: b)
        }
        let c = CompareResult(user: UserRef(username: "kenji", name: "Kenji"), media: .anime, rows: [
            row("a", 50, 90), row("b", 90, 90), row("c", 100, 95), row("d", 80, nil), row("e", 70, 85),
        ])
        XCTAssertEqual(c.inCommon, 5)
        XCTAssertEqual(c.scoredByBoth, 4)
        XCTAssertEqual(c.apartText, "1.5")  // (40 + 0 + 5 + 15) / 4 / 10
        XCTAssertEqual(c.mostDifferent.map(\.id), ["a", "e", "c", "b"])
        XCTAssertEqual(c.bestTogether.map(\.id), ["c", "b", "e", "a"])
        XCTAssertEqual(c.rows[0].caption, "4 apart")
        XCTAssertEqual(c.rows[1].caption, "Same score")
        XCTAssertEqual(c.rows[2].caption, "0.5 apart")
        XCTAssertEqual(c.subtitle, "Anime · both lists")
    }

    // MARK: fixtures

    func testProfileFixtureDecodes() throws {
        let p = try Demo.load(ProfilePage.self, "api/profile.json")
        XCTAssertEqual(p.user.username, "mika")
        XCTAssertEqual(p.friendsLabel, "6 friends")
        XCTAssertFalse(p.favourites.isEmpty)
        XCTAssertEqual(p.reviews.count, p.reviewCount)
        XCTAssertEqual(p.comments.count, p.commentCount)
        XCTAssertTrue(p.joinedLine.hasPrefix("Joined "))
        XCTAssertNotNil(p.banner)
    }

    func testFriendsFixturesDecode() throws {
        let friends = ["kenji", "noor.reads", "tobiwan", "lena", "sorawatches", "hal"]
        for name in friends {
            let u = try Demo.load(UserPage.self, Demo.file("users/" + name))
            XCTAssertEqual(u.user.username, name)
            XCTAssertEqual(Set(u.summaries.map(\.media)), Set(MediaKind.allCases))
            for s in u.summaries {
                XCTAssertEqual(ListStatus.ordered.reduce(0) { $0 + s.count($1) }, s.entries, name)
            }
            XCTAssertFalse(u.lastUpdates.isEmpty)
            for m in MediaKind.allCases {
                let c = try Demo.load(CompareResult.self, Demo.file("compare/" + name, variant: m.rawValue))
                XCTAssertEqual(c.media, m)
                XCTAssertEqual(c.inCommon, u.inCommon(m), "\(name) \(m)")
            }
        }
        let k = try Demo.load(UserPage.self, "api/users/kenji.json")
        XCTAssertEqual(k.joinedLine, "Joined Mar 12, 2026 · Friends since Oct")
        XCTAssertTrue(k.isFriend)
        XCTAssertEqual(k.friendshipLabel, "Friends")
    }

    func testComparesThroughTheDemoTransport() async throws {
        let api = APIClient(transport: DemoTransport(offline: false), token: "demo")
        let c = try await api.compare("kenji", media: .anime)
        XCTAssertGreaterThan(c.scoredByBoth, 4)
        let u = try await api.userPage("kenji")
        XCTAssertEqual(u.user.username, "kenji")
        let p = try await api.profilePage()
        XCTAssertEqual(p.user.username, "mika")
    }
}
