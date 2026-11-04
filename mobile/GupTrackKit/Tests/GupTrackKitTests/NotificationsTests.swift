import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// The bell (08): GET notices, POST notices/seen (docs/app-api.md §6).
final class NotificationsTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func notices() throws -> [BellNotice] { try Demo.load([BellNotice].self, "api/notices.json") }

    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder.decode(T.self, from: Data(json.utf8))
    }

    func testDecodesTheDocsShape() throws {
        let list = try decode([BellNotice].self, """
        [{"key":"episode:anime:21:1151","kind":"episode","ref":{"kind":"anime","id":"21"},"title":"A Show",
          "cover":"https://img.example/c.jpg","text":"Episode 1151 is out","at":0,"seenAt":1793700000000,"unseen":true},
         {"key":"like:activity:5:9","kind":"like","ref":null,"user":"sam","item":{"to":"activity","id":5},
          "title":"Sam and 2 others","cover":"/media/avatars/sam.jpg","text":"Liked your update on A Show",
          "at":1793600000000,"seenAt":1793600000000,"unseen":false},
         {"key":"reply:review:x:3","kind":"reply-to-you","ref":null,"user":"sam",
          "item":{"to":"review","username":"jo","kind":"movie","id":"693134"},"title":"Sam","cover":"",
          "text":"Replied to you on Jo’s review of A Film","at":1,"seenAt":1,"unseen":false,"extra":1},
         {"key":"friend-request:sam:1","kind":"friend-request","ref":null,"user":"sam","title":"Sam","cover":"",
          "text":"Wants to be friends","at":1,"seenAt":1,"unseen":false}]
        """)
        XCTAssertEqual(list.map(\.kind), [.episode, .like, .replyToYou, .friendRequest])
        XCTAssertEqual(list[0].ref, TitleRef(kind: .anime, id: "21"))
        XCTAssertEqual(list[0].date, Millis.date(1_793_700_000_000), "at 0: when it first showed up")
        XCTAssertEqual(list[1].item, .activity(id: 5))
        XCTAssertEqual(list[1].cover?.relativeString, "/media/avatars/sam.jpg")
        XCTAssertNil(list[2].cover)
        XCTAssertEqual(list[2].item, .review(username: "jo", kind: .movie, id: "693134"))
        // writes back the same shape
        let again = try APIClient.decoder.decode([BellNotice].self, from: JSONEncoder().encode(list))
        XCTAssertEqual(again, list)
    }

    func testRoutes() throws {
        let list = try notices()
        func first(_ k: BellNotice.Kind) throws -> BellNotice { try XCTUnwrap(list.first { $0.kind == k }) }
        XCTAssertEqual(try first(.friendRequest).route(), .user("aoi_reads"))
        XCTAssertEqual(try first(.message).route(), .conversation("kenji"))
        XCTAssertEqual(try first(.comment).route(me: "mika"), .user("mika"), "a comment is on your profile")
        XCTAssertEqual(try first(.like).route(), .review("mika:anime:154587"))
        XCTAssertEqual(try first(.reply).route(), .activity("8811"))
        XCTAssertEqual(try first(.episode).route(), .title("anime:210482"))
        XCTAssertEqual(try first(.sequel).route(), .title("anime:181641"))
        XCTAssertEqual(try first(.friendAccepted).route(), .user("sorawatches"))
    }

    func testSentences() throws {
        let list = try notices()
        let req = try XCTUnwrap(list.first { $0.kind == .friendRequest })
        XCTAssertEqual(req.sentence, "Aoi wants to be friends")
        XCTAssertEqual(req.runs.first, BellNotice.Run(text: "Aoi", strong: true))
        let like = try XCTUnwrap(list.first { $0.kind == .like })
        XCTAssertTrue(like.sentence.hasPrefix("Tobi and 2 others liked your review of "), like.sentence)
        let ep = try XCTUnwrap(list.first { $0.kind == .episode })
        XCTAssertTrue(ep.sentence.hasSuffix(" · Episode 6 is out"), ep.sentence)
        XCTAssertFalse(ep.leadsWithPerson)
        let msg = try XCTUnwrap(list.first { $0.kind == .message })
        XCTAssertEqual(msg.sentence, "Kenji sent you a message: “Gyro’s steel ball bit is my whole personality now”")
        var more = msg
        more.text = "3 new messages: “See you Friday”"
        XCTAssertEqual(more.sentence, "Kenji sent you 3 new messages: “See you Friday”")
        XCTAssertTrue(req.leadsWithPerson)
    }

    func testCaptions() throws {
        let list = try notices()
        let req = try XCTUnwrap(list.first { $0.kind == .friendRequest })
        XCTAssertEqual(req.caption(), "12 min ago")
        let ep = try XCTUnwrap(list.first { $0.kind == .episode })
        let sbr = Demo.library().first { $0.id == "anime:210482" }
        XCTAssertEqual(ep.caption(entry: sbr), "Fri · you're on 5 of 11")
        let old = try XCTUnwrap(list.first { $0.kind == .friendAccepted })
        XCTAssertEqual(old.caption(), "Oct 21")
    }

    func testSectionsAndTheDot() throws {
        let list = try notices()
        let sections = NoticeSection.of(list)
        XCTAssertEqual(sections.map(\.name), ["Today", "This week", "Earlier"])
        XCTAssertEqual(sections.first?.items.first?.kind, .friendRequest)
        XCTAssertEqual(sections.flatMap(\.items).count, list.count)
        XCTAssertEqual(NoticeSection.unseen(list), 4)
    }

    func testCalls() async throws {
        let t = StubTransport()
        let api = APIClient(transport: t, token: "demo-token")
        t.reply("[]")
        _ = try await api.notices()
        t.reply(#"{"ok":true}"#)
        _ = try await api.markNoticesSeen()
        XCTAssertEqual(t.sent.map { "\($0.method) \($0.path)" }, ["GET notices", "POST notices/seen"])
        XCTAssertTrue(t.sent.allSatisfy { $0.query.isEmpty })
    }
}
