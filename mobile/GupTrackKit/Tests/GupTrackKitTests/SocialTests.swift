import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// Social (44-54): the fixtures decode, and the sentences, times, filters and chat grouping come out as drawn.
final class SocialTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func load<T: Decodable>(_ type: T.Type, _ path: String) throws -> T { try Demo.load(type, path) }

    // MARK: activity

    func testFeedIsTheMockupsOrder() throws {
        let feed = try load(ActivityFeed.self, "api/social/activity.json")
        XCTAssertEqual(feed.items.map(\.user.username).prefix(5),
                       ["kenji", "noor.reads", "tobiwan", "lena", "sorawatches"])
        let k = feed.items[0]
        XCTAssertEqual(k.object, "Frieren: Beyond Journey’s End")
        XCTAssertEqual(k.metaBefore, "Anime")
        XCTAssertEqual(k.score10, "9")
        XCTAssertEqual(SocialText.feedTime(k.at), "12m")
        XCTAssertEqual(SocialText.feedTime(feed.items[1].at), "1h")
        XCTAssertEqual(SocialText.feedTime(feed.items[3].at), "Yesterday")
        XCTAssertEqual(feed.items[3].titles?.count, 4)
        XCTAssertEqual(feed.items[4].metaBefore, "TV · Season 2")
        XCTAssertNotNil(feed.items[2].quote)
        XCTAssertTrue(k.ratedInThread)
        XCTAssertFalse(feed.items[2].ratedInThread)
    }

    func testEveryFeedItemHasAThread() throws {
        let feed = try load(ActivityFeed.self, "api/social/activity.json")
        for item in feed.items {
            let t = try load(ActivityThread.self, Demo.file("activity/" + item.id))
            XCTAssertEqual(t.item, item)
            XCTAssertEqual(t.replies.count, item.replies, item.id)
        }
    }

    func testThreadLikedByLine() throws {
        let t = try load(ActivityThread.self, "api/activity/a1.json")
        let l = SocialText.likedBy(t.likedBy, likes: t.item.likes)
        XCTAssertEqual(l?.name, "tobiwan")
        XCTAssertEqual(l?.rest, "and 4 others")
        XCTAssertNil(SocialText.likedBy([], likes: 0))
        XCTAssertEqual(SocialText.likedBy([UserRef(username: "a", name: "a", avatar: nil)], likes: 1)?.rest, "")
        XCTAssertEqual(SocialText.likedBy([UserRef(username: "a", name: "a", avatar: nil)], likes: 2)?.rest, "and 1 other")
        XCTAssertEqual(SocialText.agoWords(t.item.at), "12 minutes ago")
        XCTAssertEqual(SocialText.repliesHeading(2), "2 replies")
        XCTAssertEqual(SocialText.repliesHeading(1), "1 reply")
    }

    func testLikeToggles() throws {
        let item = try load(ActivityFeed.self, "api/social/activity.json").items[0]
        XCTAssertTrue(item.liked)
        let off = item.toggledLike()
        XCTAssertFalse(off.liked)
        XCTAssertEqual(off.likes, item.likes - 1)
        XCTAssertEqual(off.toggledLike(), item)
    }

    // MARK: friends

    func testFriendsPage() throws {
        let p = try load(FriendsPage.self, "api/friends.json")
        XCTAssertEqual(p.requests.count, 2)
        XCTAssertEqual(p.requests[0].line, "15 in common · 12m")
        XCTAssertEqual(p.requests[1].line, "5 in common · 4d")
        XCTAssertEqual(p.friends.count, 6)
        XCTAssertEqual(p.friends[0].line, "38 in common · Active now")
        XCTAssertTrue(p.friends[0].online)
        XCTAssertEqual(p.sent.count, 1)
        XCTAssertEqual(p.blocked.count, 1)

        let accepted = p.accepting(p.requests[0].id)
        XCTAssertEqual(accepted.requests.count, 1)
        XCTAssertEqual(accepted.friends.first?.id, p.requests[0].id)
        XCTAssertEqual(p.declining("jun.k").requests.map(\.id), [p.requests[0].id])
        XCTAssertTrue(p.cancelling(p.sent[0].id).sent.isEmpty)
        XCTAssertTrue(p.unblocking(p.blocked[0].username).blocked.isEmpty)
    }

    func testFindSomeone() throws {
        XCTAssertEqual(FriendSearch.query("  @Kobeni "), "kobeni")
        let hit = try load(FriendSearch.self, Demo.file("users/search", variant: "kobeni"))
        XCTAssertEqual(hit.user?.user.username, "kobeni")
        XCTAssertEqual(hit.user?.line, "198 titles · 19 in common")
        XCTAssertEqual(hit.user?.friend, false)
        let none = try load(FriendSearch.self, "api/users/search.json")
        XCTAssertNil(none.user)
        let friend = try load(FriendSearch.self, Demo.file("users/search", variant: "noor.reads"))
        XCTAssertEqual(friend.user?.friend, true)
    }

    // MARK: reviews

    func testReviewsPage() throws {
        let p = try load(ReviewsPage.self, Demo.file("titles/anime:154587/reviews"))
        XCTAssertEqual(p.title.name, "Frieren: Beyond Journey’s End")
        XCTAssertEqual(Format.average(p.average), "8.7")
        XCTAssertEqual(p.averageLine, "average of 52 reviews")
        XCTAssertEqual(p.friendCount, 3)
        let liked = ReviewsPage.shown(p.reviews, sort: .liked, spoilers: false)
        XCTAssertEqual(liked.prefix(3).map(\.user.username), ["makima.fan", "powerpower", "noor.reads"])
        XCTAssertFalse(liked.contains(where: \.spoiler))
        XCTAssertEqual(ReviewsPage.shown(p.reviews, sort: .newest).first?.user.username, "kenji")
        XCTAssertEqual(ReviewsPage.shown(p.reviews, sort: .highest).first?.score10, "10")
        XCTAssertEqual(ReviewsPage.shown(p.reviews, sort: .lowest).first?.score10, "6")
        XCTAssertEqual(ReviewsPage.shown(p.reviews, sort: .liked, friendsOnly: true).count, 3)
        XCTAssertEqual(Set(ReviewsPage.shown(p.reviews, sort: .liked, nearScore: 90).map(\.score)), [80, 90, 95, 100])
    }

    func testEveryReviewHasAThread() throws {
        for id in ["anime:154587", "anime:210482", "manga:105778", "movie:693134", "tv:95396"] {
            let p = try load(ReviewsPage.self, Demo.file("titles/\(id)/reviews"))
            XCTAssertEqual(p.title.id, id)
            for r in p.reviews {
                let t = try load(ReviewThread.self, Demo.file("reviews/" + r.id))
                XCTAssertEqual(t.review, r)
                XCTAssertEqual(t.title.id, id)
                XCTAssertEqual(t.replies.count, min(r.replies, 2))
            }
        }
    }

    // MARK: messages

    func testMessageList() throws {
        let l = try load(MessageList.self, "api/messages.json")
        XCTAssertEqual(l.unread, 2)
        XCTAssertEqual(l.requestLine, "aki.h wants to message you")
        XCTAssertEqual(l.conversations.map(\.time), ["9:12", "8:40", "Yesterday", "Sun", "Fri", "Oct 27"])
        XCTAssertEqual(l.conversations[1].preview, "You: Sent you Andor")
        XCTAssertEqual(l.conversations[0].preview, "Gyro spinning those steel balls is all I think about now")
        XCTAssertEqual(l.markingRead(["kenji"]).unread, 0)
        var two = l
        two.requests.append(MessageList.Request(user: UserRef(username: "x", name: "x", avatar: nil), at: Clock.demoNow))
        XCTAssertEqual(two.requestLine, "aki.h and 1 other want to message you")
    }

    func testEveryConversationLoads() throws {
        let l = try load(MessageList.self, "api/messages.json")
        for row in l.conversations + [] {
            let c = try load(Conversation.self, Demo.file("conversations/" + row.id))
            XCTAssertEqual(c.user.username, row.id)
            XCTAssertFalse(c.messages.isEmpty)
        }
        _ = try load(Conversation.self, Demo.file("conversations/aki.h"))
    }

    func testKenjiChatLines() throws {
        let c = try load(Conversation.self, "api/conversations/kenji.json")
        XCTAssertTrue(c.typing)
        let lines = Conversation.lines(c.messages)
        func describe(_ l: Conversation.Line) -> String {
            switch l {
            case .stamp(let s): return "[" + s + "]"
            case .bubble(let m, let tail): return m.id + (tail ? "^" : "")
            case .read(let s): return "(" + s + ")"
            }
        }
        XCTAssertEqual(lines.map(describe), ["[Yesterday 11:40 PM]", "k1", "k2^", "k3", "k4^", "(Read 12:03 AM)",
                                             "[Today 9:10 AM]", "k5", "k6^", "k7^"])
        XCTAssertEqual(c.messages[3].title.map(SocialText.cardLine), "Anime · 11 eps · Fall 2026")
        XCTAssertEqual(Set(lines.map(\.id)).count, lines.count, "ids are unique")
    }

    func testSendingAndReacting() throws {
        let c = try load(Conversation.self, "api/conversations/kenji.json")
        let m = Conversation.Message(id: "new", fromMe: true, text: "hi", title: nil, at: Clock.demoNow,
                                     reaction: nil, read: nil)
        let sent = c.sending(m)
        XCTAssertEqual(sent.messages.last?.id, "new")
        if case .bubble(let last, let tail) = Conversation.lines(sent.messages).last {
            XCTAssertEqual(last.id, "new")
            XCTAssertTrue(tail)
        } else { XCTFail("the sent message is last") }
        XCTAssertEqual(c.reacting("k5", "🔥").messages[4].reaction, "🔥")
        XCTAssertNil(c.reacting("k6", "❤️").messages[5].reaction, "the same reaction again takes it off")
    }

    func testMessageRequest() throws {
        let r = try load(MessageRequest.self, "api/message-requests/aki.h.json")
        XCTAssertEqual(r.user.username, "aki.h")
        XCTAssertEqual(r.line, "Not a friend · 287 titles · 16 in common")
        XCTAssertEqual(r.messages.count, 2)
        XCTAssertEqual(r.messages.first.map { SocialText.stamp($0.at) }, "Today 8:02 AM")
    }

    // MARK: words

    func testTimes() {
        let now = Clock.demoNow
        XCTAssertEqual(SocialText.listTime(now.addingTimeInterval(-29 * 60)), "9:12")
        XCTAssertEqual(SocialText.feedTime(now.addingTimeInterval(-3 * 86_400)), "Sat")
        XCTAssertEqual(SocialText.feedTime(now.addingTimeInterval(-10 * 86_400)), "Oct 24")
        XCTAssertEqual(SocialText.agoWords(now.addingTimeInterval(-60)), "1 minute ago")
        XCTAssertEqual(SocialText.agoWords(now.addingTimeInterval(-6 * 86_400)), "Oct 28")
        XCTAssertEqual(SocialText.stamp(now.addingTimeInterval(-10 * 86_400)), "Oct 24 10:41 AM", "daylight time then")
    }

    func testCardLines() {
        var t = Make.title()
        t.media = .movie; t.total = nil; t.runtime = "2h 47m"; t.season = nil; t.year = 2024
        XCTAssertEqual(SocialText.cardLine(t), "Movie · 2h 47m · 2024")
        t.media = .manga; t.total = 1; t.year = nil
        XCTAssertEqual(SocialText.cardLine(t), "Manga · 1 ch")
        t.media = .book; t.total = 320
        XCTAssertEqual(SocialText.cardLine(t), "Book · 320 pages")
    }

    func testPostsEncodeWithoutEmptyFields() throws {
        let d = try APIClient.encoder.encode(SocialPost(text: "hi"))
        XCTAssertEqual(String(data: d, encoding: .utf8), #"{"text":"hi"}"#)
    }
}
