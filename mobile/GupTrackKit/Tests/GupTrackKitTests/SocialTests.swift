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

/// Social (44-54) on the app API (§10, §11): the doc's shapes decode, each call asks for what the doc says, the
/// feed folds and words its lines like the website, and the chat groups its bubbles.
final class SocialTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private let now = Millis.of(Clock.demoNow)

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder.decode(type, from: Data(json.utf8))
    }

    private func body(_ r: APIRequest?) -> JSONValue? {
        r?.body.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
    }

    private static let fran = #"{ "username": "fran", "name": "Fran", "avatar": "/media/u/fran/avatar-3f2a.webp", "relation": "friend", "open": true, "lists": ["anime", "manga", "tv", "movies", "books"], "since": 1793724823948 }"#

    // MARK: people

    func testPersonDecodesTheDocsExample() throws {
        let p = try decode(Person.self, Self.fran)
        XCTAssertEqual(p.username, "fran")
        XCTAssertEqual(p.relation, .friend)
        XCTAssertEqual(p.lists, APIMedia.allCases)
        XCTAssertEqual(p.avatar?.absoluteString, "/media/u/fran/avatar-3f2a.webp")   // resolved by the image loader
        XCTAssertEqual(p.since, 1_793_724_823_948)
        let someone = try decode(Person.self, #"{"username":"x","name":"","avatar":null,"relation":"none","open":false,"lists":[],"extra":1}"#)
        XCTAssertNil(someone.since)
        XCTAssertEqual(someone.user.name, "x", "no name shows the username")
        XCTAssertEqual(try decode(Person.self, #"{"username":"me","name":"Me","avatar":null,"relation":"self","open":true,"lists":[]}"#).relation, .me)
    }

    func testFriendsStateMovesPeopleBetweenLists() throws {
        let s = try decode(FriendsState.self, """
        { "friends": [\(Self.fran)], "incoming": [{"username":"ash","name":"","avatar":null,"relation":"incoming","open":true,"lists":["anime"],"since":1793716000000}],
          "outgoing": [{"username":"bo","name":"Bo","avatar":null,"relation":"outgoing","open":true,"lists":[],"since":1793600000000}],
          "blocked": ["troll"], "visibility": "public",
          "lists": {"anime":"public","manga":"friends","tv":"public","movies":"private","books":"public"} }
        """)
        XCTAssertEqual(s.lists["movies"], .private)
        XCTAssertEqual(s.blocked, ["troll"])
        let accepted = s.accepting("ash", now: Clock.demoNow)
        XCTAssertEqual(accepted.incoming.count, 0)
        XCTAssertEqual(accepted.friends.first?.username, "ash")
        XCTAssertEqual(accepted.friends.first?.relation, .friend)
        XCTAssertEqual(FriendsState.line(accepted.friends[0], now: Clock.demoNow), "Friends since Nov 2026")
        XCTAssertEqual(s.declining("ash").incoming.count, 0)
        XCTAssertEqual(s.cancelling("bo").outgoing.count, 0)
        XCTAssertEqual(s.unblocking("troll").blocked, [])
        XCTAssertEqual(FriendsState.line(s.incoming[0], now: Clock.demoNow), "Asked 14m")
        XCTAssertEqual(FriendsState.line(s.outgoing[0]), "Sent Nov 2")
        XCTAssertEqual(FriendSearch.query("  @Kenji "), "kenji")
    }

    func testFriendCallsAskForWhatTheDocSays() async throws {
        let t = StubTransport()
        let api = APIClient(transport: t, token: "x")
        t.reply(#"{"relation":"outgoing"}"#)
        let asked = try await api.requestFriend("fran")
        XCTAssertEqual(asked, .outgoing)
        XCTAssertEqual(t.sent.last?.method, "POST")
        XCTAssertEqual(t.sent.last?.path, "users/fran/friend")
        t.reply(#"{"relation":"friend"}"#)
        let answered = try await api.answerFriend("fran", accept: true)
        XCTAssertEqual(answered, .friend)
        XCTAssertEqual(t.sent.last?.path, "users/fran/friend/answer")
        XCTAssertEqual(body(t.sent.last), .object(["accept": .bool(true)]))
        t.reply(#"{"ok":true}"#)
        _ = try await api.cancelFriendRequest("fran")
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["DELETE", "users/fran/friend/request"])
        _ = try await api.unfriend("fran")
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["DELETE", "users/fran/friend"])
        _ = try await api.block("fran")
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["POST", "users/fran/block"])
        _ = try await api.unblock("fran")
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["DELETE", "users/fran/block"])
        t.reply(Self.fran)
        let found = try await api.findPerson("fran")
        XCTAssertEqual(found?.name, "Fran")
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["GET", "users/fran/person"])
        t.reply(#"{"error":"not_found","message":"No such user.","serverTime":1}"#, 404)
        let nobody = try await api.findPerson("nobody")
        XCTAssertNil(nobody, "404 is nobody, not an error")
        t.reply(#"{"error":"forbidden","message":"No.","serverTime":1}"#, 403)
        do { _ = try await api.findPerson("x"); XCTFail("a 403 is an error") } catch {}
    }

    // MARK: activity and the feed

    private func activity(_ id: Int, _ type: String, _ before: String, _ after: String, media: String = "anime",
                          at: Int64 = 0, user: String = "fran", entry: String = "154587",
                          title: String = "Frieren") -> String {
        """
        {"id":\(id),"at":\(at),"media":"\(media)","entry":"\(entry)","title":"\(title)","cover":"","type":"\(type)",
         "before":\(before),"after":\(after),
         "social":{"target":{"on":"activity","id":\(id)},"likes":0,"liked":false,"likers":[],"replies":0,"canLike":true},
         "user":{"username":"\(user)","name":"","avatar":null,"relation":"friend","open":true,"lists":["anime"]}}
        """
    }

    func testFriendActivityIsOneFlatObject() throws {
        let a = try decode(FriendActivity.self, activity(7, "status", #""current""#, #""completed""#, at: now))
        XCTAssertEqual(a.id, 7)
        XCTAssertEqual(a.user.username, "fran")
        XCTAssertEqual(a.activity.titleId, "anime:154587")
        XCTAssertEqual(a.activity.social?.target, Reactions.Target(on: "activity", id: 7))
        let imp = try decode(FriendActivity.self, """
        {"id":8,"at":1,"media":"anime","entry":null,"title":"","cover":"","type":"import","before":null,
         "after":{"added":3,"updated":2},"user":\(Self.fran)}
        """)
        XCTAssertNil(imp.activity.titleCard)
        XCTAssertNil(imp.activity.social)
        XCTAssertEqual(Feed.words(imp.activity)?.verb, "imported 5 titles from")
        XCTAssertEqual(Feed.words(imp.activity)?.object, "a file")
        // it writes back flat too
        let again = try APIClient.decoder.decode(FriendActivity.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(again, a)
    }

    func testFeedSentencesFollowTheWebsite() throws {
        func w(_ type: String, _ b: String, _ a: String, _ media: String = "anime") throws -> String? {
            let x = try decode(FriendActivity.self, activity(1, type, b, a, media: media)).activity
            return Feed.words(x).map { "\($0.verb) [\($0.object)]\($0.tail)" }
        }
        XCTAssertEqual(try w("added", "null", #""planned""#), "added [Frieren] to Plan to Watch")
        XCTAssertEqual(try w("added", "null", #""planned""#, "books"), "added [Frieren] to Plan to Read")
        XCTAssertEqual(try w("status", #""planned""#, #""current""#), "started [Frieren]")
        XCTAssertEqual(try w("status", #""hold""#, #""current""#), "resumed [Frieren]")
        XCTAssertEqual(try w("status", #""current""#, #""hold""#), "put [Frieren] on hold")
        XCTAssertEqual(try w("status", #""current""#, #""rewatching""#), "started rewatching [Frieren]")
        XCTAssertEqual(try w("status", #""current""#, #""rewatching""#, "manga"), "started rereading [Frieren]")
        XCTAssertEqual(try w("progress", "6", "9"), "watched eps 7–9 of [Frieren]")
        XCTAssertEqual(try w("progress", "11", "12", "manga"), "read ch 12 of [Frieren]")
        XCTAssertEqual(try w("progress", "9", "4"), "went back to ep 4 of [Frieren]")
        XCTAssertEqual(try w("progress", "0", "1", "movies"), "watched [Frieren]")
        XCTAssertEqual(try w("score", "null", "null"), "took the score off [Frieren]")
        XCTAssertEqual(try w("repeats", "0", "1"), "rewatched [Frieren]")
        XCTAssertEqual(try w("removed", #""current""#, "null"), "removed [Frieren] from their list")
        XCTAssertEqual(try w("review", "null", "null"), "reviewed [Frieren]")
        XCTAssertNil(try w("position", "10", "20"))
        XCTAssertNil(try w("progress", "3", "3"))
        let rated = try decode(FriendActivity.self, activity(1, "score", "null", "85")).activity
        XCTAssertEqual(Feed.words(rated)?.score, 85)
    }

    func testFeedFoldsCompletedAndGroupsAdds() throws {
        let t = now - 600_000
        let log = try decode([FriendActivity].self, "[" + [
            activity(9, "score", "null", "90", at: t + 120_000),
            activity(8, "status", #""current""#, #""completed""#, at: t),
            activity(7, "progress", "27", "28", at: t - 800),
            activity(6, "added", "null", #""planned""#, media: "tv", at: t - 3_600_000, user: "lena", entry: "1", title: "A"),
            activity(5, "added", "null", #""planned""#, media: "tv", at: t - 3_640_000, user: "lena", entry: "2", title: "B"),
            activity(4, "added", "null", #""planned""#, media: "tv", at: t - 3_680_000, user: "lena", entry: "3", title: "C"),
            activity(3, "score", "null", "70", at: t - 86_400_000, user: "hal"),
        ].joined(separator: ",") + "]")
        let lines = Feed.lines(log)
        XCTAssertEqual(lines.map(\.id), [8, 6, 3])
        XCTAssertEqual(lines[0].verb, "completed")
        XCTAssertEqual(lines[0].score, 90, "the score given right after finishing goes on the Completed line")
        XCTAssertEqual(lines[0].score10, "9")
        XCTAssertEqual(lines[1].object, "3 shows")
        XCTAssertEqual(lines[1].tail, " to Plan to Watch")
        XCTAssertEqual(lines[1].titles.map(\.name), ["A", "B", "C"])
        XCTAssertNil(lines[1].social, "a group has no one thread to like")
        XCTAssertEqual(lines[2].verb, "rated")
        XCTAssertEqual(lines[2].score, 70)
        XCTAssertEqual(lines[0].toggledLike().social?.likes, 1)
    }

    func testDemoFeed() throws {
        let feed = try Demo.load(FeedAnswer.self, "api/feed.json").activity
        let lines = Feed.lines(feed)
        XCTAssertEqual(lines.first?.user.username, "kenji")
        XCTAssertEqual(lines.first?.verb, "completed")
        XCTAssertEqual(lines.first?.score10, "9")
        XCTAssertEqual(SocialText.feedTime(lines[0].at), "12m")
        XCTAssertTrue(lines.contains { $0.object == "4 shows" && $0.titles.count == 4 })
        for l in feed {
            let item = try Demo.load(ActivityItem.self, "api/activity/\(l.id).json").item
            XCTAssertEqual(item.id, l.id)
            if let s = l.activity.social {
                let r = try Demo.load(Replies.self, Demo.file("replies/\(s.target.on)/\(s.target.id)"))
                XCTAssertEqual(r.replies.count, s.replies, "\(l.id)")
                XCTAssertNotNil(try? Demo.load(ReactionsAnswer.self, Demo.file("likes/\(s.target.on)/\(s.target.id)", method: "POST")))
            }
        }
    }

    // MARK: likes and replies

    func testLikesAndReplies() async throws {
        let t = StubTransport()
        let api = APIClient(transport: t, token: "x")
        let r = #"{"target":{"on":"activity","id":7},"likes":2,"liked":true,"likers":[\#(Self.fran)],"replies":1,"canLike":true}"#
        t.reply(#"{"reactions":\#(r)}"#)
        let got = try await api.like(Reactions.Target(on: "activity", id: 7), true)
        XCTAssertEqual(got.likes, 2)
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["POST", "likes/activity/7"])
        XCTAssertEqual(body(t.sent.last), .object(["like": .bool(true)]))
        XCTAssertEqual(got.likedBy?.name, "fran")
        XCTAssertEqual(got.likedBy?.rest, "and 1 other")
        let off = got.toggledLike(me: Person(username: "fran", relation: .me))
        XCTAssertEqual(off.likes, 1)
        XCTAssertFalse(off.liked)
        XCTAssertTrue(off.likers.isEmpty)

        let reply = #"{"id":3,"parent":null,"author":\#(Self.fran),"body":"yes","at":1,"edited":null,"canEdit":false,"canDelete":true}"#
        t.reply(#"{"replies":[\#(reply)],"reactions":\#(r)}"#)
        let thread = try await api.replies(Reactions.Target(on: "review", id: 12))
        XCTAssertEqual(thread.replies.first?.body, "yes")
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["GET", "replies/review/12"])
        t.reply(#"{"reply":\#(reply)}"#)
        _ = try await api.reply(Reactions.Target(on: "activity", id: 7), "yes", parent: 3)
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["POST", "replies/activity/7"])
        XCTAssertEqual(body(t.sent.last), .object(["body": .string("yes"), "parent": .number(3)]))
        _ = try await api.editReply(3, "no")
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["PATCH", "replies/3"])
        t.reply(#"{"ok":true}"#)
        _ = try await api.deleteReply(3)
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["DELETE", "replies/3"])
        t.reply(#"{"activity":[]}"#)
        _ = try await api.feed(before: 99)
        XCTAssertEqual(t.sent.last?.path, "feed")
        XCTAssertEqual(t.sent.last?.query, [URLQueryItem(name: "before", value: "99")])
    }

    /// the demo answers a reply on the threads the screen tests open (activity 119, review 12)
    func testDemoTakesReplies() async throws {
        let api = APIClient(transport: DemoTransport(), token: "demo")
        for target in [Reactions.Target(on: "activity", id: 119), Reactions.Target(on: "review", id: 12)] {
            let thread = try await api.replies(target)
            XCTAssertFalse(thread.replies.isEmpty)
            let mine = try await api.reply(target, "same here")
            XCTAssertEqual(mine.author.relation, .me)
        }
    }

    // MARK: reviews

    private func review(_ id: Int, _ user: String, relation: String = "none", score: String = "80", likes: Int = 0,
                        at: Int64 = 1, spoiler: Bool = false) -> String {
        """
        {"id":\(id),"author":{"username":"\(user)","name":"","avatar":null,"relation":"\(relation)","open":true,"lists":[]},
         "title":{"media":"anime","id":"154587","title":"Frieren","cover":"","format":"TV"},
         "body":"Good.","cut":false,"spoiler":\(spoiler),"score":\(score),"at":\(at),"edited":null,
         "social":{"target":{"on":"review","id":\(id)},"likes":\(likes),"liked":false,"likers":[],"replies":0,"canLike":true}}
        """
    }

    func testTitleReviewsSortFilterAndAverage() throws {
        let page = try decode(TitleReviews.self, """
        {"mine":\(review(1, "me", relation: "self", score: "null")),
         "reviews":[\(review(2, "fran", relation: "friend", score: "90", likes: 1, at: 30)),
                    \(review(3, "ash", score: "60", likes: 9, at: 20)),
                    \(review(4, "bo", score: "100", likes: 3, at: 10, spoiler: true))],
         "visibility":"friends"}
        """)
        XCTAssertEqual(page.count, 4)
        XCTAssertEqual(page.average.map { Format.average($0) }, "8.3")
        XCTAssertEqual(page.averageLine, "average of 4 reviews")
        XCTAssertEqual(page.friendCount, 1)
        XCTAssertEqual(page.reviews[0].key, "anime:154587@fran")
        XCTAssertEqual(ReviewKey("anime:154587@fran")?.username, "fran")
        XCTAssertEqual(ReviewKey("anime:154587@a@b")?.username, "b")
        XCTAssertNil(ReviewKey("nope"))
        let all = page.reviews
        XCTAssertEqual(TitleReviews.shown(all, sort: .liked, spoilers: true).map(\.id), [3, 4, 2])
        XCTAssertEqual(TitleReviews.shown(all, sort: .newest, spoilers: true).map(\.id), [2, 3, 4])
        XCTAssertEqual(TitleReviews.shown(all, sort: .highest, spoilers: true).map(\.id), [4, 2, 3])
        XCTAssertEqual(TitleReviews.shown(all, sort: .lowest, spoilers: true).map(\.id), [3, 2, 4])
        XCTAssertEqual(TitleReviews.shown(all, sort: .newest, friendsOnly: true, spoilers: true).map(\.id), [2])
        XCTAssertEqual(page.replacing(page.reviews[1].toggledLike()).reviews[1].likes, 10)
    }

    func testReviewCalls() async throws {
        let t = StubTransport()
        let api = APIClient(transport: t, token: "x")
        t.reply(#"{"mine":null,"reviews":[],"visibility":"public"}"#)
        _ = try await api.titleReviews("anime:154587")
        XCTAssertEqual(t.sent.last?.path, "titles/anime/154587/reviews")
        _ = try await api.titleReviews("movie:693134")
        XCTAssertEqual(t.sent.last?.path, "titles/movie/693134/reviews", "the singular kind, as on a title page")
        t.reply(review(2, "fran"))
        let one = try await api.review(ReviewKey(titleId: "anime:154587", username: "fran"))
        XCTAssertEqual(one.id, 2)
        XCTAssertEqual(t.sent.last?.path, "users/fran/reviews/anime/154587")
        t.reply(#"{"person":\#(Self.fran),"reviews":[],"total":0}"#)
        _ = try await api.reviews(of: "fran", limit: 3)
        XCTAssertEqual(t.sent.last?.path, "users/fran/reviews")
        XCTAssertEqual(t.sent.last?.query, [URLQueryItem(name: "limit", value: "3")])
        _ = try await api.reviews()
        XCTAssertEqual(t.sent.last?.path, "reviews")
        t.reply(#"{"friends":[{"user":\#(Self.fran),"status":"completed","score":90,"progress":28,"total":28,"rewatching":false,"repeats":0,"notes":""}]}"#)
        let watching = try await api.titleFriends("anime:154587")
        XCTAssertEqual(watching.first?.status, .completed)
        XCTAssertEqual(t.sent.last?.path, "titles/anime/154587/friends")
    }

    func testDemoReviews() throws {
        let page = try Demo.load(TitleReviews.self, "api/titles/anime/154587/reviews.json")
        XCTAssertEqual(page.mine?.author.username, "mika")
        XCTAssertEqual(page.reviews.first?.author.relation, .friend, "friends first")
        for r in page.all {
            let whole = try Demo.load(Review.self, Demo.file("users/\(r.author.username)/reviews/anime/154587"))
            XCTAssertEqual(whole.id, r.id)
            _ = try Demo.load(Replies.self, Demo.file("replies/review/\(r.id)"))
        }
        let mine = try Demo.load(UserReviews.self, "api/reviews.json")
        XCTAssertEqual(mine.person.relation, .me)
        XCTAssertEqual(mine.total, mine.reviews.count)
        _ = try Demo.load(FriendEntries.self, "api/titles/anime/154587/friends.json")
    }

    // MARK: messages

    private static let message = #"""
    { "id": 1, "mine": true, "body": "hi fran!",
      "card": { "kind": "anime", "id": "154587", "title": "Frieren: Beyond Journey’s End", "cover": "https://s4.anilist.co/x.jpg", "format": "TV", "year": 2023 },
      "photos": [ { "src": "/dm/photo/demo-photo-1.jpg", "thumb": "/dm/photo/demo-photo-1-t.webp",
                    "width": 64, "height": 48 } ],
      "at": 1793724838596, "edited": 1793724839131, "deleted": false, "reactions": [ { "emoji": "🔥", "mine": false } ] }
    """#

    func testMessageDecodesTheDocsExample() throws {
        let m = try decode(Message.self, Self.message)
        XCTAssertEqual(m.card?.titleId, "anime:154587")
        XCTAssertEqual(m.card?.line, "Anime · TV · 2023")
        XCTAssertNil(m.card?.status)
        XCTAssertEqual(m.photos.first?.name, "demo-photo-1.jpg")
        XCTAssertEqual(m.photos.first?.src.absoluteString, "/dm/photo/demo-photo-1.jpg")
        let fire = m.reacting("❤️")
        XCTAssertEqual(fire.reactions.map(\.emoji), ["🔥", "❤️"])
        XCTAssertEqual(fire.reacting("😂").reactions.filter(\.mine).map(\.emoji), ["😂"], "one each: a new one replaces yours")
        XCTAssertEqual(fire.reacting("❤️").reactions.filter(\.mine).count, 0, "the same one takes it back")
    }

    private func line(_ user: String, unread: Int, muted: Bool = false, last: String? = #"{"mine":true,"text":"Shared Andor","at":1793716000000}"#) -> String {
        #"{"person":{"username":"\#(user)","name":"","avatar":null,"relation":"friend","open":true,"lists":[]},"last":\#(last ?? "null"),"unread":\#(unread),"muted":\#(muted)}"#
    }

    func testMessageListAndPulse() async throws {
        let t = StubTransport()
        let api = APIClient(transport: t, token: "x")
        t.reply(#"{"lines":[\#(line("a", unread: 2)),\#(line("b", unread: 1, muted: true)),\#(line("c", unread: 0, last: nil))],"requests":0}"#)
        let list = try await api.messageList()
        XCTAssertEqual(t.sent.count, 1, "no requests: no second call")
        XCTAssertEqual(t.sent.last?.path, "messages")
        XCTAssertEqual(list.unread, 1, "muted ones left out")
        XCTAssertEqual(list.lines[0].preview, "You: Shared Andor")
        XCTAssertEqual(list.lines[2].preview, "")
        XCTAssertNil(list.requestLine)
        XCTAssertEqual(list.markingRead(["a"]).unread, 0)

        t.reply(#"{"lines":[\#(line("aki", unread: 2))],"requests":1}"#)
        let waiting = try await api.messages(requests: true)
        XCTAssertEqual(t.sent.last?.query, [URLQueryItem(name: "box", value: "requests")])
        let withRequests = MessageList(lines: [], requestLines: waiting.lines, requests: 1)
        XCTAssertEqual(withRequests.requestLine, "aki wants to message you")
        XCTAssertNil(withRequests.answering(["aki"]).requestLine)

        t.reply(#"{"unread":2,"requests":1,"stamp":1793716000000,"typing":["fran"]}"#)
        let p = try await api.pulse()
        XCTAssertEqual(p.typing, ["fran"])
        XCTAssertEqual(t.sent.last?.path, "messages/pulse")
        t.reply(#"{"recipient":null}"#)
        let none = try await api.findRecipient("nobody")
        XCTAssertNil(none)
        XCTAssertEqual(t.sent.last?.path, "messages/recipients/nobody")
    }

    func testConversationLines() throws {
        func m(_ id: Int, _ mine: Bool, _ minutesAgo: Int) -> Message {
            Message(id: id, mine: mine, body: "\(id)", card: nil, photos: [], at: now - Int64(minutesAgo) * 60_000,
                    edited: nil, deleted: false, reactions: [])
        }
        let ms = [m(1, false, 600), m(2, false, 599), m(3, true, 590), m(4, true, 589), m(5, false, 20)]
        let lines = Conversation.lines(ms, seen: 4)
        XCTAssertEqual(lines.map(\.id), ["stamp Yesterday 11:41 PM", "m1", "m2", "m3", "m4", "read", "stamp Today 9:21 AM", "m5"])
        let tails = lines.compactMap { l -> Bool? in if case .bubble(_, let t) = l { return t }; return nil }
        XCTAssertEqual(tails, [false, true, false, true, true])
        XCTAssertFalse(Conversation.lines(ms, seen: 2).contains(.read), "they haven't read any of yours")
        XCTAssertFalse(Conversation.lines(ms, seen: nil).contains(.read))
    }

    func testMessageCalls() async throws {
        let t = StubTransport()
        let api = APIClient(transport: t, token: "x")
        t.reply(#"{"person":\#(Self.fran),"box":"inbox","messages":[\#(Self.message)],"more":true,"seen":1,"muted":false,"canSend":true}"#)
        let c = try await api.conversation("fran", before: 40)
        XCTAssertEqual(c.seen, 1)
        XCTAssertNil(c.why)
        XCTAssertEqual(t.sent.last?.path, "conversations/fran")
        XCTAssertEqual(t.sent.last?.query, [URLQueryItem(name: "before", value: "40")])
        XCTAssertEqual(c.reacting(1, "😮").messages[0].reactions.last, Reaction(emoji: "😮", mine: true))

        t.reply(#"{"message":\#(Self.message)}"#)
        _ = try await api.sendMessage("fran", OutgoingMessage(body: "hi", card: .init(kind: .anime, id: "154587", mine: true)),
                                      requestId: "demo-1")
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["POST", "conversations/fran/messages"])
        XCTAssertEqual(t.sent.last?.requestId, "demo-1")
        XCTAssertEqual(body(t.sent.last), .object(["body": .string("hi"),
                                                    "card": .object(["kind": .string("anime"), "id": .string("154587"), "mine": .bool(true)])]))
        t.reply(#"{"ok":true}"#)
        _ = try await api.react(1, nil)
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["POST", "messages/1/reaction"])
        XCTAssertEqual(body(t.sent.last), .object(["emoji": .null]), "null takes the reaction back")
        _ = try await api.react(1, "🔥")
        XCTAssertEqual(body(t.sent.last), .object(["emoji": .string("🔥")]))
        _ = try await api.markRead("fran")
        XCTAssertEqual(t.sent.last?.path, "conversations/fran/read")
        _ = try await api.answerMessageRequest("fran", accept: false)
        XCTAssertEqual(t.sent.last?.path, "conversations/fran/answer")
        XCTAssertEqual(body(t.sent.last), .object(["accept": .bool(false)]))
        _ = try await api.mute("fran", true)
        XCTAssertEqual(body(t.sent.last), .object(["muted": .bool(true)]))
        _ = try await api.typing("fran")
        XCTAssertEqual(t.sent.last?.path, "conversations/fran/typing")
        _ = try await api.editMessage(1, "edited")
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["PATCH", "messages/1"])
        _ = try await api.deleteMessage(1)
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["DELETE", "messages/1"])
        _ = try await api.clearConversation("fran")
        XCTAssertEqual(t.sent.last?.path, "conversations/fran/clear")
        _ = try await api.deletePhoto("9d32.jpg")
        XCTAssertEqual([t.sent.last?.method, t.sent.last?.path], ["DELETE", "messages/photos/9d32.jpg"])
        t.reply(#"{"photo":{"src":"/dm/photo/a.jpg","thumb":"/dm/photo/a-t.webp","width":4,"height":3}}"#)
        let photo = try await api.uploadPhoto(Data([1, 2]), contentType: "image/jpeg")
        XCTAssertEqual(photo.name, "a.jpg")
        XCTAssertEqual(t.sent.last?.path, "messages/photos")
        XCTAssertEqual(t.sent.last?.contentType, "image/jpeg")
    }

    func testLiveEventsParseTheDocsStream() {
        var s = LiveStream()
        let events = s.feed(text: """
        retry: 5000
        : hello

        data: {"t":"message","with":"fran"}

        data: {"t":"typing","with":"fran"}

        : beat
        data: {"t":"read","with":"ash"}

        data: {"t":"change"}

        data: {"t":"change","with":"bo"}

        data: {"t":"later","with":"x"}

        retry: 9000

        """)
        XCTAssertEqual(events, [.message("fran"), .typing("fran"), .read("ash"), .change(nil), .change("bo")])
        XCTAssertEqual(s.retry, 9000)
        XCTAssertNil(LiveEvent(json: Data(#"{"t":"message"}"#.utf8)), "a message event names who")
    }

    func testDemoMessages() throws {
        let inbox = try Demo.load(MessagesAnswer.self, "api/messages.json")
        XCTAssertEqual(inbox.lines.first?.person.username, "kenji")
        XCTAssertEqual(inbox.requests, 1)
        let waiting = try Demo.load(MessagesAnswer.self, "api/messages/requests.json")
        XCTAssertEqual(waiting.lines.map(\.person.username), ["aki.h"])
        let pulse = try Demo.load(Pulse.self, "api/messages/pulse.json")
        XCTAssertEqual(pulse.unread, MessageList(lines: inbox.lines, requestLines: [], requests: 1).unread)
        for l in inbox.lines + waiting.lines {
            let c = try Demo.load(Conversation.self, Demo.file("conversations/\(l.person.username)"))
            XCTAssertEqual(c.messages.last.map { $0.at }, l.last?.at, l.person.username)
        }
        let kenji = try Demo.load(Conversation.self, "api/conversations/kenji.json")
        XCTAssertTrue(kenji.messages.contains { $0.body == "binged it last night!! up to ep 5" })
        XCTAssertTrue(kenji.lines().contains(.read))
        XCTAssertTrue(try Demo.load(Conversation.self, "api/conversations/aki.h.json").isRequest)
        XCTAssertFalse(try Demo.load(Conversation.self, "api/conversations/kobeni.json").canSend)
        _ = try Demo.load(MessageAnswer.self, Demo.file("conversations/kenji/messages", method: "POST"))
        _ = try Demo.load(RecipientAnswer.self, "api/messages/recipients/kenji.json")
    }

    func testDemoPeople() throws {
        let f = try Demo.load(FriendsState.self, "api/friends.json")
        XCTAssertEqual(f.friends.count, 6)
        XCTAssertEqual(f.incoming.first?.username, "nami.watches")
        for p in f.friends + f.incoming + f.outgoing {
            XCTAssertEqual(try Demo.load(Person.self, Demo.file("users/\(p.username)/person")), p)
        }
        XCTAssertEqual(try Demo.load(RelationAnswer.self, Demo.file("users/nami.watches/friend/answer", method: "POST")).relation, .friend)
        XCTAssertEqual(FriendSearch.line(try Demo.load(Person.self, "api/users/yuki.tv/person.json")), "Profile hidden")
    }
}
