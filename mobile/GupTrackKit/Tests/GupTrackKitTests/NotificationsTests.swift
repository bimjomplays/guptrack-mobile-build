import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// Notifications (08): the demo feed, its sentences, captions, sections and where a tap goes.
final class NotificationsTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func feed() throws -> NotificationFeed { try Demo.load(NotificationFeed.self, "api/notifications.json") }
    private func library() throws -> [LibraryEntry] { try Demo.load([LibraryEntry].self, "api/library.json") }

    private func item(_ id: String) throws -> NotificationFeed.Item {
        try XCTUnwrap(try feed().items.first { $0.id == id })
    }

    func testSectionsAreTodayThisWeekEarlier() throws {
        let s = NotificationFeed.sections(try feed().items)
        XCTAssertEqual(s.map(\.name), ["Today", "This week", "Earlier"])
        XCTAssertEqual(s[0].items.map(\.kind), [.friendRequest, .message, .comment, .like])
        XCTAssertEqual(s[1].items.map(\.kind), [.reply, .episode, .sequel, .release])
        XCTAssertEqual(NotificationFeed.unreadCount(try feed().items), 4)
    }

    func testEveryKindIsInTheDemo() throws {
        let kinds = Set(try feed().items.map(\.kind))
        XCTAssertEqual(kinds, [.friendRequest, .message, .comment, .like, .reply, .episode, .sequel, .release])
        let me = try Demo.load(UserRef.self, "api/me.json")
        XCTAssertFalse(try feed().items.contains { $0.user?.username == me.username }, "nobody notifies themselves")
    }

    func testSentences() throws {
        XCTAssertEqual(try item("n1").sentence(), "aoi_reads wants to be friends")
        XCTAssertEqual(try item("n2").sentence(), "kenji sent you a message: “Gyro’s steel ball bit is my whole personality now”")
        XCTAssertEqual(try item("n3").sentence(), "noor.reads commented on your profile: “Rezero solos?? we need to talk”")
        XCTAssertEqual(try item("n4").sentence(), "tobiwan and 2 others liked your review of Cyberpunk: Edgerunners")
        XCTAssertEqual(try item("n4").runs().filter(\.strong).map(\.text), ["tobiwan", "Cyberpunk: Edgerunners"])
        XCTAssertEqual(try item("n6").sentence(), "A sequel was announced: Dandadan 3rd Season")
        XCTAssertEqual(try item("n7").sentence(), "Witch on the Holy Night, on your Plan to Watch, comes out Thu, Nov 19")
        XCTAssertEqual(try item("n8").sentence(), "hal replied to your comment on ONE PIECE")
        XCTAssertEqual(try item("n9").sentence(), "lena liked your update on Cyberpunk: Edgerunners 2")
        let sbr = try item("n5")
        XCTAssertEqual(sbr.runs().first, NotificationFeed.Run(text: "Episode 6", strong: true))
        XCTAssertTrue(sbr.sentence().hasPrefix("Episode 6 of STEEL BALL RUN"))
        XCTAssertTrue(sbr.sentence().hasSuffix(" is out"))
    }

    func testTheLibrarysStatusWinsInReleases() throws {
        var n = try item("n7")
        let e = Make.entry(n.title!.id, .current)
        XCTAssertTrue(n.sentence(entry: e).contains("on your Watching"))
        n.status = nil
        XCTAssertEqual(n.sentence(), "Witch on the Holy Night comes out Thu, Nov 19")
    }

    func testCaptions() throws {
        let lib = try library()
        XCTAssertEqual(try item("n1").caption(), "12 min ago · 12 titles in common")
        XCTAssertEqual(try item("n3").caption(), "1 hour ago")
        let sbr = try item("n5")
        let e = lib.first { $0.id == sbr.title?.id }
        XCTAssertNotNil(e)
        let total = e?.title.total.map { " of \($0)" } ?? ""
        XCTAssertEqual(sbr.caption(entry: e), "Fri, Oct 30 · you're on \(e!.progress)\(total)")
        XCTAssertEqual(sbr.caption(), "Fri, Oct 30")
        XCTAssertEqual(try item("n6").caption(), "Thu · comes 2027")
        XCTAssertEqual(try item("n7").caption(), "Wed")
        XCTAssertEqual(try item("n8").caption(), "Mon")
        XCTAssertEqual(try item("n10").caption(), "Oct 21")
    }

    func testTapsOpenTheRightPage() throws {
        XCTAssertEqual(try item("n1").route, .user("aoi_reads"))
        XCTAssertEqual(try item("n2").route, .conversation("kenji"))
        XCTAssertEqual(try item("n3").route, .activity("act-noor-profile"))
        XCTAssertEqual(try item("n4").route, .review("rev-mika-120377"))
        XCTAssertEqual(try item("n5").route, .title("anime:210482"))
        XCTAssertEqual(try item("n6").route, .title("anime:198966"))
        XCTAssertEqual(try item("n7").route, .title("anime:143103"))
        XCTAssertEqual(try item("n8").route, .activity("act-hal-21"))
        XCTAssertEqual(try item("n9").route, .activity("act-mika-195539"))
        XCTAssertTrue(try item("n2").leadsWithPerson)
        XCTAssertFalse(try item("n5").leadsWithPerson)
        XCTAssertTrue(try item("n4").showsThumb)
        XCTAssertFalse(try item("n2").showsThumb)
    }

    func testCallsGoToTheRightPaths() async throws {
        let t = DemoTransport()
        let api = APIClient(transport: t)
        let f = try await api.notifications()
        XCTAssertEqual(f.items.count, 10)
        let read = try await api.markNotificationsRead()
        XCTAssertTrue(read.ok)
        let yes = try await api.answerFriendRequest("aoi_reads", accept: true)
        XCTAssertTrue(yes.ok)
        _ = try await api.answerFriendRequest("aoi_reads", accept: false)
        XCTAssertEqual(t.requests.map { "\($0.method) \($0.path)" }, [
            "GET notifications", "POST notifications/read", "POST friends/requests/aoi_reads/accept",
            "POST friends/requests/aoi_reads/decline",
        ])
    }
}
