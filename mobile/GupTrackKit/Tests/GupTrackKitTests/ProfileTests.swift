import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// Profiles (41-43b, 48, 49; docs/app-api.md §10.2, §10.4): the numbers come from the server's answer (MediaStats,
/// KindStats, Comparison) and the screens' words are worked out from them.
final class ProfileTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder.decode(type, from: Data(json.utf8))
    }

    private func body(_ r: APIRequest?) -> JSONValue? {
        r?.body.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
    }

    private static let fran = #"{"username":"fran","name":"Fran","avatar":null,"relation":"friend","open":true,"lists":["anime","manga"],"since":1790000000000}"#

    private func stats(_ media: String, amount: Double = 45.3, counts: String = #"{"completed":40,"planned":10}"#) -> String {
        #"{"media":"\#(media)","entries":57,"counts":\#(counts),"meanScore":82.8,"scored":38,"amount":\#(amount),"progress":1204,"repeats":2,"favourites":3}"#
    }

    private func entry(_ id: String, status: String = "current", progress: Int = 6, score: String = "null",
                       updated: Double = 0.5) -> String {
        #"""
        {"id":"\#(id)","title":"T\#(id)","alt":[],"cover":"","format":"TV","status":"\#(status)","progress":\#(progress),"total":12,
         "score":\#(score),"minutes":24,"updated":\#(updated),"position":0,"volumes":null,"readVolumes":0,"repeats":0,"rewatch":null,
         "started":null,"finished":null,"notes":"","favourite":false,"idMal":null,"added":1}
        """#
    }

    // MARK: numbers per list

    func testMediaStatsColumns() throws {
        let anime = try decode(MediaStats.self, stats("anime"))
        XCTAssertEqual(anime.columns.map(\.label), ["Days", "Mean score", "Rewatched", "Episodes"])
        XCTAssertEqual(anime.columns.map(\.value), ["45.3", "8.28", "2", "1,204"])
        XCTAssertEqual(anime.percent(.completed), "70%")
        XCTAssertEqual(anime.count(.dropped), 0)
        let manga = try decode(MediaStats.self, stats("manga", amount: 1958))
        XCTAssertEqual(manga.columns.map(\.label), ["Chapters", "Mean score", "Reread", "Completed"])
        XCTAssertEqual(manga.columns[0].value, "1,958")
        XCTAssertEqual(manga.columns[3].value, "40")
        let books = try decode(MediaStats.self, stats("books", amount: 2462))
        XCTAssertEqual(books.columns.map(\.label), ["Pages", "Mean score", "Reread", "Books read"])
        let films = try decode(MediaStats.self, stats("movies", amount: 0.94))
        XCTAssertEqual(films.columns.map(\.value), ["0.9", "8.28", "2", "40"])
        XCTAssertEqual(films.columns[3].label, "Films")
        XCTAssertEqual(MediaStats.empty(.tv).meanText, "–")
    }

    func testBioReadsTheBannerFadeAndWords() throws {
        let bio = try decode(JSONValue.self, #"""
        {"style":{"accent":"brand"},"banner":{"src":"/media/u/fran/banner-1.webp","posX":50,"posY":40,"zoom":1,"aspect":3,
          "fade":{"on":true,"strength":60,"color":"dark","text":"auto"}},
         "doc":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Slow "},{"type":"text","text":"manga."}]},
                {"type":"paragraph","content":[{"type":"text","text":"One book"},{"type":"hardBreak"},{"type":"text","text":"a month."}]}]}}
        """#)
        let b = ProfileBio(bio)
        XCTAssertEqual(b.banner?.absoluteString, "/media/u/fran/banner-1.webp")
        XCTAssertEqual(b.fade, 0.6, accuracy: 0.0001)
        XCTAssertEqual(b.text, "Slow manga.\nOne book\na month.")
        let off = try decode(JSONValue.self, #"{"banner":{"src":"x.jpg","fade":{"on":false,"strength":60}},"doc":null}"#)
        XCTAssertEqual(ProfileBio(off).fade, 0)
        XCTAssertEqual(ProfileBio(nil), ProfileBio())
        XCTAssertNil(ProfileBio(nil).banner)
    }

    // MARK: your profile

    func testMyProfileDecodesTheDocsShape() throws {
        let p = try decode(MyProfile.self, #"""
        {"profile":{"name":"Fran","avatar":null,"bio":null,"joined":1757428860000},
         "friends":{"count":1,"incoming":2},
         "stats":[\#(stats("anime"))],
         "characters":[{"id":"1","name":"Frieren","image":"https://s4.anilist.co/c.png","sub":"Frieren"}],
         "names":[{"kind":"studio","id":"11","name":"MADHOUSE","image":"","sub":"Studio"}],
         "reviews":{"person":\#(Self.fran),"reviews":[],"total":0},
         "lists":{"profile":"public","lists":[{"id":4,"slug":"comfort","name":"Comfort","description":"","count":3,
                   "covers":["https://s4.anilist.co/a.jpg",null],"media":["anime"],"updated":1}]},
         "comments":{"comments":[],"canPost":true,"setting":"friends"},
         "at":1793716000000,"later":true}
        """#)
        XCTAssertEqual(p.friendsLabel, "1 friend")
        XCTAssertEqual(p.friends.incoming, 2)
        XCTAssertEqual(p.joinedLine, "Joined Sep 9, 2025")
        XCTAssertEqual(p.stats(.anime).entries, 57)
        XCTAssertEqual(p.stats(.book).entries, 0, "a missing list is empty")
        XCTAssertEqual(p.lists.lists.first?.coverURLs.count, 1)
        XCTAssertEqual(p.names.first?.kind, "studio")
        XCTAssertEqual(p.comments.setting, "friends")
    }

    func testDemoProfileCarriesItsOwnStats() throws {
        // the profile's numbers are the server's (MediaStats), not added up from Demo.library()
        let p = try Demo.load(MyProfile.self, "api/profile.json")
        XCTAssertEqual(p.profile.name, "Mika")
        XCTAssertEqual(Set(p.stats.map(\.kind)), Set(MediaKind.allCases))
        let anime = p.stats(.anime)
        XCTAssertEqual(anime.entries, anime.counts.values.reduce(0, +))
        XCTAssertGreaterThan(anime.amount, 0)
        XCTAssertGreaterThan(p.stats(.tv).amount, 0)
        XCTAssertFalse(p.bio.text.isEmpty)
        XCTAssertNotNil(p.bio.banner)
        XCTAssertEqual(p.friends.count, try Demo.load(FriendsState.self, "api/friends.json").friends.count)
        let stats = try Demo.load(StatsPage.self, "api/stats.json")
        for k in stats.kinds {
            XCTAssertEqual(k.entries, p.stats(k.kind).entries, "\(k.kind)")
            XCTAssertEqual(k.meanScore, p.stats(k.kind).meanScore, accuracy: 0.01)
        }
        let comments = try Demo.load(CommentsState.self, "api/comments.json")
        XCTAssertEqual(comments.comments.map(\.id), p.comments.comments.map(\.id))
    }

    // MARK: someone's profile

    func testUserProfileLinesAndUpdates() throws {
        let u = try decode(UserProfile.self, #"""
        {"person":\#(Self.fran),"profile":{"joined":1757428860000,"bio":null,"characters":[],"names":[]},
         "stats":[\#(stats("anime")),\#(stats("manga"))],
         "lists":{"anime":[\#(entry("1", updated: 2)),\#(entry("2", status: "completed", progress: 12, score: "90", updated: 0.1))],
                  "manga":[\#(entry("3", status: "planned", progress: 0, updated: 1))]},
         "activity":[],"mutual":[]}
        """#)
        XCTAssertEqual(u.joinedLine(), "Joined Sep 9, 2025 · Friends since Sep", "this year: the month only")
        let ups = u.lastUpdates()
        XCTAssertEqual(ups.map(\.title.id), ["anime:2", "manga:3", "anime:1"])
        XCTAssertEqual(ups.map(\.caption), ["Completed · ★9", "Plan to Read", "Ep 6 of 12"])
        XCTAssertEqual(u.entries(.manga).count, 1)
        let mine = Demo.library()
        XCTAssertEqual(u.inCommon(.anime, mine: mine), 0)
        let closed = try decode(UserProfile.self, #"""
        {"person":{"username":"yo","name":"","avatar":null,"relation":"none","open":false,"lists":[]},
         "profile":null,"stats":[],"lists":{},"activity":[],"mutual":[]}
        """#)
        XCTAssertEqual(closed.joinedLine(), "")
        XCTAssertNil(closed.firstMedia)
        XCTAssertTrue(closed.lastUpdates().isEmpty)
    }

    func testDemoPeoplesProfiles() throws {
        let mine = Demo.library()
        let kenji = try Demo.load(UserProfile.self, "api/users/kenji.json")
        XCTAssertEqual(kenji.person.relation, .friend)
        XCTAssertGreaterThan(kenji.inCommon(.anime, mine: mine), 0)
        XCTAssertEqual(kenji.lastUpdates().first?.title.id, "anime:154587", "Frieren, just finished in the feed")
        XCTAssertTrue(kenji.joinedLine().contains("Friends since"))
        for m in MediaKind.allCases {
            let lib = try Demo.load(UserLibrary.self, "api/users/kenji/library/\(m.api.rawValue).json")
            XCTAssertEqual(lib.entries.count, kenji.entries(m).count, "\(m)")
        }
        XCTAssertNil(try Demo.load(UserProfile.self, "api/users/yuki.tv.json").profile, "a closed profile shows no more")
        for p in try Demo.load(FriendsState.self, "api/friends.json").friends {
            let u = try Demo.load(UserProfile.self, Demo.file("users/\(p.username)"))
            XCTAssertEqual(u.person.username, p.username)
            _ = try Demo.load(StatsPage.self, Demo.file("users/\(p.username)/stats"))
            _ = try Demo.load(CommentsState.self, Demo.file("users/\(p.username)/comments"))
            _ = try Demo.load(UserActivityAnswer.self, Demo.file("users/\(p.username)/activity"))
        }
        _ = try Demo.load(CommentAnswer.self, Demo.file("users/kenji/comments", method: "POST"))
    }

    // MARK: statistics

    private func kind(_ media: String, scores: String, years: String = "[]", seconds: Double = 0, progress: Int = 0) -> String {
        #"""
        {"media":"\#(media)","entries":20,"counts":{"completed":12,"planned":5,"current":3},"progress":\#(progress),"again":0,"volumes":0,
         "seconds":\#(seconds),"againSeconds":3600,"repeats":1,"favourites":0,"meanScore":80,"scored":6,"scores":\#(scores),
         "formats":[{"name":"ONA","count":2,"mean":0,"scored":0},{"name":"TV","count":15,"mean":82.5,"scored":5}],
         "genres":[{"name":"Drama","count":4,"mean":80,"scored":2},{"name":"Action","count":4,"mean":70,"scored":1}],
         "makers":[{"name":"MADHOUSE","id":"11","count":3,"mean":90,"scored":3}],
         "years":\#(years),"added":[{"at":"2026-10","count":2}],"finished":[],"pending":1}
        """#
    }

    func testKindStatsWorkOutTheStatsPage() throws {
        let k = try decode(KindStats.self, kind("anime", scores: "[[100,2],[85,1],[80,2],[5,1],[0,4]]",
                                                 years: #"[{"year":1998,"count":1},{"year":2012,"count":0},{"year":2024,"count":3}]"#,
                                                 seconds: 3_916_800, progress: 2775))
        XCTAssertEqual(k.histogram, [1, 0, 0, 0, 0, 0, 0, 2, 1, 2])
        XCTAssertEqual(k.median, 8.25)
        XCTAssertEqual(k.medianText, "8.3")
        XCTAssertEqual(k.perfect, 2)
        XCTAssertEqual(k.meanText, "8.00")
        XCTAssertEqual(k.timeHeadline.main, "45 days")
        XCTAssertEqual(k.timeHeadline.rest, "9 hours", "rewatching counts")
        XCTAssertEqual(k.timeLine, "2,775 episodes · 20 entries · 15 watched or watching")
        XCTAssertEqual(k.formatSlices.map(\.label), ["TV", "ONA"])
        XCTAssertEqual(k.genreGroups.map(\.name), ["Action", "Drama"])
        XCTAssertEqual(k.genreGroups[0].meanText, "7.0")
        XCTAssertNil(KindStats.Group(name: "x", count: 1, mean: 0, scored: 0, id: nil).meanText)
        XCTAssertEqual(k.makerGroups.first?.key, "11")
        XCTAssertEqual(k.makersLabel, "Studios")
        XCTAssertEqual(k.yearSlices.map(\.label), ["’95", "’00", "’05", "’10", "’15", "’20"])
        XCTAssertEqual(k.yearSlices.map(\.count), [1, 0, 0, 0, 0, 3])
        XCTAssertEqual(KindStats.yearBuckets([.init(year: 1962, count: 1), .init(year: 2024, count: 1)]).map(\.label),
                       ["’60", "’70", "’80", "’90", "’00", "’10", "’20"], "more than 8 five-year bars: ten-year bars")
        XCTAssertEqual(KindStats.yearBuckets([.init(year: 2016, count: 2), .init(year: 2024, count: 1)]).map(\.label),
                       ["’15", "’20"])
        XCTAssertEqual(k.shareText(name: "Fran"),
                       "Fran’s anime on GupTrack: 45 days 9 hours watched, mean score 8.00, 20 entries")
        let manga = try decode(KindStats.self, kind("manga", scores: "[]", progress: 1))
        XCTAssertEqual(manga.timeHeadline.main, "1")
        XCTAssertEqual(manga.timeHeadline.rest, "chapter")
        XCTAssertNil(manga.median)
        XCTAssertEqual(manga.medianText, "–")
        XCTAssertEqual(manga.makersLabel, "Authors")
        XCTAssertEqual(KindStats.bucket(85), 9)
        XCTAssertEqual(KindStats.bucket(5), 1)
    }

    func testDemoStats() throws {
        let page = try Demo.load(StatsPage.self, "api/stats.json")
        XCTAssertEqual(page.person.relation, .me)
        let anime = try XCTUnwrap(page.kind(.anime))
        XCTAssertEqual(anime.histogram.reduce(0, +), anime.scored)
        XCTAssertFalse(anime.makerGroups.isEmpty)
        XCTAssertTrue(anime.makerGroups.allSatisfy { $0.id != nil }, "studios carry their AniList id")
        XCTAssertFalse(anime.yearSlices.isEmpty)
        XCTAssertGreaterThan(page.kind(.book)?.progress ?? 0, 0)
    }

    // MARK: compare

    private func compared(_ id: String, mine: String?, theirs: String?) -> String {
        func side(_ s: String?) -> String { s.map { #"{"status":"completed","score":\#($0),"progress":12}"# } ?? "null" }
        return #"{"media":"anime","id":"\#(id)","title":"T\#(id)","cover":"","format":"TV","mine":\#(side(mine)),"theirs":\#(side(theirs))}"#
    }

    func testComparisonWorksOutApartAndOrder() throws {
        let c = try decode(Comparison.self, #"""
        {"person":\#(Self.fran),
         "shared":[\#(compared("1", mine: "90", theirs: "50")),\#(compared("2", mine: "95", theirs: "100")),
                   \#(compared("3", mine: "null", theirs: "80")),\#(compared("4", mine: "70", theirs: "70"))],
         "theirsOnly":[\#(compared("5", mine: nil, theirs: "60"))],
         "counts":{"anime":{"mine":10,"theirs":8,"shared":4}}}
        """#)
        XCTAssertEqual(c.media, [.anime])
        let set = c.on(.anime)
        XCTAssertEqual(set.inCommon, 4)
        XCTAssertEqual(set.scoredByBoth, 3)
        XCTAssertEqual(set.mostDifferent.map(\.id), ["1", "2", "4"])
        XCTAssertEqual(set.bestTogether.map(\.id), ["2", "4", "1"])
        XCTAssertEqual(set.apartText, "1.5")
        XCTAssertEqual(set.mostDifferent.map(\.caption), ["4 apart", "0.5 apart", "Same score"])
        XCTAssertEqual(set.subtitle, "Anime · both lists")
        XCTAssertNil(c.on(.manga).apartAverage)
        XCTAssertEqual(c.on(.manga).apartText, "–")
        XCTAssertEqual(c.theirsOnly.first?.mine, nil)
        XCTAssertEqual(c.shared[0].titleId, "anime:1")
    }

    func testDemoCompare() throws {
        let c = try Demo.load(Comparison.self, "api/users/kenji/compare.json")
        XCTAssertEqual(c.person.username, "kenji")
        let anime = c.on(.anime)
        XCTAssertEqual(anime.inCommon, anime.rows.count)
        XCTAssertGreaterThan(anime.scoredByBoth, 0)
        XCTAssertFalse(c.theirsOnly.isEmpty)
        XCTAssertTrue(c.shared.allSatisfy { $0.mine != nil && $0.theirs != nil })
    }

    // MARK: the calls

    func testProfileCallsAskForWhatTheDocSays() async throws {
        let t = StubTransport()
        let api = APIClient(transport: t, token: "x")
        t.reply(#"{"person":\#(Self.fran),"profile":null,"stats":[],"lists":{},"activity":[],"mutual":[]}"#)
        _ = try await api.userProfile("fran")
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["GET", "users/fran"])
        t.reply(#"{"person":\#(Self.fran),"entries":[\#(entry("1"))]}"#)
        let lib = try await api.userLibrary("fran", .movie)
        XCTAssertEqual(lib.entries.count, 1)
        XCTAssertEqual(t.sent.last?.path, "users/fran/library/movies")
        t.reply(#"{"activity":[]}"#)
        _ = try await api.userActivity("fran", before: 5)
        XCTAssertEqual(t.sent.last?.path, "users/fran/activity")
        XCTAssertEqual(t.sent.last?.query, [URLQueryItem(name: "before", value: "5")])
        t.reply(#"{"person":\#(Self.fran),"shared":[],"theirsOnly":[],"counts":{}}"#)
        _ = try await api.compare("fran")
        XCTAssertEqual(t.sent.last?.path, "users/fran/compare")
        t.reply(#"{"person":\#(Self.fran),"kinds":[]}"#)
        _ = try await api.stats()
        XCTAssertEqual(t.sent.last?.path, "stats")
        _ = try await api.stats(of: "fran")
        XCTAssertEqual(t.sent.last?.path, "users/fran/stats")
        t.reply(#"{"comments":[],"canPost":false}"#)
        let none = try await api.comments(of: "fran")
        XCTAssertNil(none.setting)
        XCTAssertEqual(t.sent.last?.path, "users/fran/comments")
        _ = try await api.comments()
        XCTAssertEqual(t.sent.last?.path, "comments")
        let c = #"{"comment":{"id":3,"author":\#(Self.fran),"body":"hi","at":1,"edited":null,"canEdit":true,"canDelete":true}}"#
        t.reply(c)
        _ = try await api.postComment(on: "fran", "hi")
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["POST", "users/fran/comments"])
        XCTAssertEqual(body(t.sent.last), .object(["body": .string("hi")]))
        _ = try await api.editComment(3, "hey")
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["PATCH", "comments/3"])
        t.reply(#"{"ok":true}"#)
        _ = try await api.deleteComment(3)
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["DELETE", "comments/3"])
        t.reply(try String(contentsOf: Demo.root.appendingPathComponent("api/profile.json"), encoding: .utf8))
        let me = try await api.myProfile()
        XCTAssertEqual(t.sent.last?.path, "profile")
        XCTAssertFalse(me.stats.isEmpty)
    }
}
