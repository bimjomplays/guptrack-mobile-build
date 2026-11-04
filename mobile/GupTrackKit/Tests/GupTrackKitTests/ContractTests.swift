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

/// The app API as docs/app-api.md writes it: each example below has the doc's shape (its keys, nesting and types)
/// with invented values, and the Kit must read it, or write it, exactly so.
final class ContractTests: XCTestCase {
    let base = URL(string: "https://guptrack.example.ts.net")!

    func decode<T: Decodable>(_ type: T.Type, _ json: String, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        do {
            return try APIClient.decoder.decode(T.self, from: Data(json.utf8))
        } catch {
            XCTFail("\(T.self) didn't decode: \(error)", file: file, line: line)
            throw error
        }
    }

    /// a body as JSON values, to compare what the app writes with the doc's example
    func json(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: data) }
    func json(_ s: String) throws -> JSONValue { try json(Data(s.utf8)) }

    // a token has the doc's shape: "gtk_" + 43 URL-safe characters (invented here)
    let token = "gtk_" + String(repeating: "Ab3-_x", count: 7) + "Q"

    // MARK: §1 the server

    func testServer() throws {
        let s = try decode(ServerInfo.self, #"{"app":"guptrack","api":1,"setupOpen":false,"serverTime":1793724171075}"#)
        XCTAssertEqual(s, ServerInfo(app: "guptrack", api: 1, setupOpen: false, serverTime: 1_793_724_171_075))
        XCTAssertEqual(ServerCheck.verdict(s, at: base).server, base)
        // v1 only ever gains fields: unknown ones are ignored
        _ = try decode(ServerInfo.self, #"{"app":"guptrack","api":1,"setupOpen":false,"serverTime":1,"newThing":{"a":1}}"#)
    }

    func testEveryCallIsUnderTheVersionedBase() {
        XCTAssertEqual(APIRequest("GET", "server").url(on: base)?.absoluteString, "https://guptrack.example.ts.net/api/app/v1/server")
        XCTAssertEqual(APIRequest("GET", "server").url(on: URL(string: "http://127.0.0.1:3000")!)?.absoluteString,
                       "http://127.0.0.1:3000/api/app/v1/server")
    }

    // MARK: §2 request ids

    func testWhichCallsCarryARequestId() {
        for (method, path) in [("POST", "notices/seen"), ("PATCH", "settings/profile"), ("DELETE", "devices/3"),
                               ("PUT", "lists/4/items"), ("POST", "auth/sign-out"), ("POST", "messages/photos")] {
            XCTAssertTrue(APIRequest.takesRequestId(method, path), "\(method) \(path)")
        }
        // GETs; the signed-out calls of §4; the calls whose answer holds a secret
        for (method, path) in [("GET", "me"), ("POST", "auth/sign-in"), ("POST", "auth/pair"), ("POST", "auth/pair/check"),
                               ("POST", "auth/join"), ("POST", "auth/recover"), ("POST", "account/password"),
                               ("POST", "account/recovery-codes"), ("POST", "devices/pairing"), ("POST", "accounts/invites")] {
            XCTAssertFalse(APIRequest.takesRequestId(method, path), "\(method) \(path)")
        }
    }

    func testRequestIdsGoInTheHeader() async throws {
        let t = StubTransport()
        t.reply(#"{"ok":true}"#)
        let api = APIClient(transport: t, token: token)
        let _: OKReply = try await api.send("POST", "notices/seen")
        let _: OKReply = try await api.send("POST", "notices/seen", requestId: "action-7")
        let _: OKReply = try await api.send("POST", "account/recovery-codes", ["password": "pw"])
        XCTAssertNotNil(t.sent[0].requestId.flatMap(UUID.init(uuidString:)), "a new UUID per action")
        XCTAssertEqual(t.sent[1].requestId, "action-7", "kept with the action while it waits")
        XCTAssertNil(t.sent[2].requestId)
        let r = try LiveTransport.makeRequest(t.sent[1], base: base)
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Request-Id"), "action-7")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer " + token)
        let none = try LiveTransport.makeRequest(t.sent[2], base: base)
        XCTAssertNil(none.value(forHTTPHeaderField: "X-Request-Id"))
        XCTAssertEqual(none.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    // MARK: §3 errors

    func testErrors() async throws {
        let t = StubTransport()
        let api = APIClient(transport: t, token: token)
        func error(_ status: Int, _ body: String, headers: [String: String] = [:]) async -> APIError? {
            t.reply(body, status, headers: headers)
            do {
                let _: OKReply = try await api.get("me")
                return nil
            } catch {
                return error as? APIError
            }
        }
        let missing = await error(404, #"{ "error": "not_found", "message": "That account isn’t here.", "serverTime": 1793724171075 }"#)
        XCTAssertEqual(missing, .server(404, "not_found", "That account isn’t here."))
        XCTAssertEqual(missing?.message, "That account isn’t here.")
        // only `unauthorized` means the token is gone; a wrong password or code while signed in is an ordinary error
        let gone = await error(401, #"{"error":"unauthorized","message":"Sign in again.","serverTime":1}"#)
        XCTAssertEqual(gone, .signedOut)
        let wrong = await error(401, #"{"error":"wrong_password","message":"That password isn’t right.","serverTime":1}"#)
        XCTAssertEqual(wrong?.code, "wrong_password")
        let busy = await error(429, #"{"error":"rate_limited","message":"Slow down.","serverTime":1}"#, headers: ["retry-after": "30"])
        XCTAssertEqual(busy, .server(429, "rate_limited", "Slow down.", retryAfter: 30))
        XCTAssertEqual(busy?.isRetryable, true)
        let expired = await error(409, #"{"error":"cursor_expired","message":"Read again.","serverTime":1}"#)
        XCTAssertEqual(expired?.code, "cursor_expired")
        XCTAssertEqual(expired?.isRetryable, false)
        let upstream = await error(502, #"{"error":"upstream_unavailable","message":"AniList didn’t answer.","serverTime":1}"#)
        XCTAssertEqual(upstream?.isRetryable, true)
    }

    // MARK: §4 signing in

    /// the doc's sign-in answer, with an invented token and person
    var signInAnswer: String {
        #"""
        {
          "token": "TOKEN",
          "device": { "id": 1, "scope": "app", "app": "GupTrack", "name": "Mika’s iPhone",
                      "platform": "iOS 26.1", "createdAt": 1793723977768, "lastUsedAt": 1793723977768 },
          "user": { "username": "mika", "role": "owner" },
          "serverTime": 1793723977768
        }
        """#.replacingOccurrences(of: "TOKEN", with: token)
    }

    func testSignInAnswer() throws {
        let a = try decode(SignInAnswer.self, signInAnswer)
        XCTAssertEqual(a.token, token)
        XCTAssertEqual(a.device, Device(id: 1, scope: "app", app: "GupTrack", name: "Mika’s iPhone", platform: "iOS 26.1",
                                        createdAt: 1_793_723_977_768, lastUsedAt: 1_793_723_977_768))
        XCTAssertEqual(a.user, Me(username: "mika", role: "owner"))
        XCTAssertNil(a.recoveryCodes)
        // joining adds ten recovery codes, recovering how many are left
        let codes = (0..<10).map { _ in "aaaaa-bbbbb-ccccc-ddddd-eeeee-f" }
        var joined = signInAnswer
        joined.removeLast(2)
        joined += #", "recoveryCodes": \#(codes.map { "\"\($0)\"" })}"#
        XCTAssertEqual(try decode(SignInAnswer.self, joined).recoveryCodes?.count, 10)
        var recovered = signInAnswer
        recovered.removeLast(2)
        recovered += #", "codesLeft": 7}"#
        XCTAssertEqual(try decode(SignInAnswer.self, recovered).codesLeft, 7)
    }

    func testSignInBodies() async throws {
        let t = StubTransport()
        t.reply(signInAnswer)
        let api = APIClient(transport: t)
        let device = DeviceInfo(name: "Mika’s iPhone", platform: "iOS 26.1")
        _ = try await api.pair(code: "7KQ4-M2XD", device: device)
        _ = try await api.signIn(username: "mika", password: "pw", device: device)
        _ = try await api.join(JoinBody(invite: "inv", username: "mika", password: "pw", device: device))
        _ = try await api.recover(RecoverBody(username: "mika", code: "c", password: "pw", device: device))
        XCTAssertEqual(t.sent.map(\.path), ["auth/pair", "auth/sign-in", "auth/join", "auth/recover"])
        XCTAssertEqual(t.sent.map(\.method), ["POST", "POST", "POST", "POST"])
        XCTAssertTrue(t.sent.allSatisfy { $0.token == nil && $0.requestId == nil })
        let dev: JSONValue = .object(["name": .string("Mika’s iPhone"), "platform": .string("iOS 26.1")])
        XCTAssertEqual(try json(t.sent[0].body!), .object(["code": .string("7KQ4-M2XD"), "device": dev]))
        XCTAssertEqual(try json(t.sent[1].body!), .object(["username": .string("mika"), "password": .string("pw"), "device": dev]))
        XCTAssertEqual(try json(t.sent[2].body!), .object(["invite": .string("inv"), "username": .string("mika"),
                                                          "password": .string("pw"), "device": dev]))
        XCTAssertEqual(try json(t.sent[3].body!), .object(["username": .string("mika"), "code": .string("c"),
                                                          "password": .string("pw"), "device": dev]))
    }

    func testDeviceNamesAreCut() {
        let d = DeviceInfo(name: String(repeating: "n", count: 80), platform: String(repeating: "p", count: 40))
        XCTAssertEqual(d.name.count, 60)
        XCTAssertEqual(d.platform.count, 30)
    }

    func testPairCheck() async throws {
        let t = StubTransport()
        t.reply(#"{"user":{"username":"mika"},"serverTime":1793724171075}"#)
        let who = try await APIClient(transport: t).checkPairing(code: "7KQ4-M2XD")
        XCTAssertEqual(who.user.username, "mika")
        XCTAssertEqual(t.sent[0].path, "auth/pair/check")
        XCTAssertEqual(try json(t.sent[0].body!), .object(["code": .string("7KQ4-M2XD")]))
    }

    /// the website writes the QR with URLSearchParams: guptrack://pair?server=<encoded>&code=<code>
    func testPairingLink() throws {
        var q = URLComponents()
        q.queryItems = [URLQueryItem(name: "server", value: "https://guptrack.example.ts.net"),
                        URLQueryItem(name: "code", value: "7KQ4-M2XD")]
        // URLSearchParams also encodes ":" and "/"
        let encoded = "server=https%3A%2F%2Fguptrack.example.ts.net&code=7KQ4-M2XD"
        for link in ["guptrack://pair?" + encoded, "guptrack://pair?" + (q.percentEncodedQuery ?? "")] {
            let p = try PairLink.parse(link).get()
            XCTAssertEqual(p.baseURL, base, link)
            XCTAssertEqual(p.code, "7KQ4-M2XD", link)
        }
    }

    func testMe() throws {
        let me = try decode(MeAnswer.self, #"""
        {
          "me": { "username": "mika", "role": "member" },
          "profile": { "name": "Mika", "avatar": "/media/avatar-1a2b.webp", "bio": null, "joined": 1791902460000 },
          "prefs": {
            "titleLanguage": "english", "scoreFormat": "100", "adult": false, "spoilers": "hide", "theme": "dark",
            "smartProgress": true, "autoDates": true, "hidden": ["books"],
            "notify": { "episodes": true, "sequels": true, "releases": false, "lists": "watching", "friends": true,
                        "comments": true, "social": true, "messages": true, "desktop": false },
            "dateFormat": "mdy", "weekStart": "monday"
          },
          "device": { "id": 3, "scope": "app", "app": "GupTrack", "name": "Mika’s iPhone", "platform": "iOS 26.1",
                      "createdAt": 1793723977768, "lastUsedAt": null },
          "serverTime": 1793724171075
        }
        """#)
        XCTAssertEqual(me.me.role, "member")
        XCTAssertEqual(me.prefs.hidden, [.books])
        XCTAssertEqual(me.device.id, 3)
        XCTAssertNil(me.device.lastUsedAt)
        let user = me.user(on: base)
        XCTAssertEqual(user.name, "Mika")
        XCTAssertEqual(user.avatar?.absoluteString, "https://guptrack.example.ts.net/api/app/v1/files/media/avatar-1a2b.webp")
        // no display name yet: the username shows
        var unnamed = me
        unnamed.profile.name = ""
        XCTAssertEqual(unnamed.user(on: base).name, "mika")
    }

    func testProfilePatch() async throws {
        let t = StubTransport()
        t.reply(#"{"profile":{"name":"Mika","avatar":null,"bio":null,"joined":1}}"#)
        let a = try await APIClient(transport: t, token: token).updateProfile(ProfilePatch(name: "Mika"))
        XCTAssertEqual(a.profile.name, "Mika")
        XCTAssertEqual(t.sent[0].method, "PATCH")
        XCTAssertEqual(t.sent[0].path, "settings/profile")
        XCTAssertEqual(try json(t.sent[0].body!), .object(["name": .string("Mika")]))
        XCTAssertNotNil(t.sent[0].requestId)
    }

    // MARK: §5 pictures

    func testPathSegments() {
        XCTAssertEqual(APIClient.segment("OL7234434A"), "OL7234434A")
        XCTAssertEqual(APIClient.segment("a/b c"), "a%2Fb%20c")
        XCTAssertEqual(APIClient.segment("café"), "caf%C3%A9")
    }

    func testPictures() {
        XCTAssertEqual(Pictures.url("/media/u/aoi_reads/banner-9f.webp", base: base)?.absoluteString,
                       "https://guptrack.example.ts.net/api/app/v1/files/media/u/aoi_reads/banner-9f.webp")
        XCTAssertEqual(Pictures.url("/dm/photo/p-77.jpg", base: base)?.absoluteString,
                       "https://guptrack.example.ts.net/api/app/v1/files/dm/photo/p-77.jpg")
        XCTAssertEqual(Pictures.url("https://s4.anilist.co/file/cover.jpg", base: base)?.absoluteString,
                       "https://s4.anilist.co/file/cover.jpg")
        XCTAssertNil(Pictures.url("http://insecure.example/x.jpg", base: base))
        XCTAssertNil(Pictures.url("", base: base))

        let saved = Pictures.signedIn
        defer { Pictures.signedIn = saved }
        Pictures.signedIn = (base, token)
        XCTAssertEqual(Pictures.authorization(for: Pictures.url("/media/a.webp", base: base)!), "Bearer " + token)
        XCTAssertNil(Pictures.authorization(for: URL(string: "https://s4.anilist.co/file/cover.jpg")!),
                     "the catalogues never see the token")
        XCTAssertNil(Pictures.authorization(for: URL(string: "https://other.example.ts.net/api/app/v1/files/media/a.webp")!))

        // a model keeps "/media/…" as it came; the loader resolves it on the signed-in server
        struct Row: Decodable { let avatar: URL? }
        let row = try? JSONDecoder().decode(Row.self, from: Data(#"{"avatar":"/media/u/aoi_reads/a-1.webp"}"#.utf8))
        let resolved = row?.avatar.flatMap(Pictures.resolve)
        XCTAssertEqual(resolved?.absoluteString, "https://guptrack.example.ts.net/api/app/v1/files/media/u/aoi_reads/a-1.webp")
        XCTAssertEqual(resolved.flatMap(Pictures.authorization), "Bearer " + token)
        XCTAssertEqual(Pictures.resolve(URL(string: "https://image.tmdb.org/t/p/w342/x.jpg")!)?.host, "image.tmdb.org")
        XCTAssertNil(Pictures.resolve(URL(string: "http://insecure.example/x.jpg")!))
        Pictures.signedIn = nil
        XCTAssertNil(Pictures.resolve(URL(string: "/media/a.webp")!), "no server to ask")
    }

    // MARK: §7.1 the change feed

    let feedExample = #"""
    {
      "entries": [
        {
          "media": "anime",
          "entry": { "id": "5114", "title": "Fullmetal Alchemist: Brotherhood", "alt": [], "cover": "https://s4.anilist.co/c.jpg",
                     "format": "TV", "status": "current", "progress": 3, "total": 64, "score": 90,
                     "minutes": 24, "updated": 0, "position": 0, "readVolumes": 0, "repeats": 0,
                     "rewatch": null, "started": "2026-11-03", "finished": null, "notes": "so good",
                     "favourite": false, "idMal": 5114, "added": 1793724170991 },
          "statusAt": 1793724170991, "progressAt": 1793724170995, "scoreAt": 1793724170998,
          "changedAt": 1793724171002, "rev": 9
        }
      ],
      "removed": [ { "media": "tv", "id": "1399", "removedAt": 1793724000000 } ],
      "lists": {
        "changed": [
          { "id": 4, "slug": "cozy-picks", "name": "Cozy picks", "description": "", "count": 1,
            "covers": ["https://s4.anilist.co/c.jpg"], "media": ["anime"], "updated": 1793724000000,
            "level": { "list": "public", "profile": "friends" },
            "items": [ { "media": "anime", "id": "5114", "title": "Fullmetal Alchemist: Brotherhood",
                         "cover": null, "format": "TV", "year": 2009, "note": "", "added": 1793724000000, "mine": "current" } ],
            "position": 0, "rev": 7 }
        ],
        "removed": [ { "id": 5, "removedAt": 1793724000000 } ]
      },
      "cursor": "epoch1.9",
      "more": false,
      "serverTime": 1793724171075
    }
    """#

    func testChangeFeed() throws {
        let f = try decode(ChangeFeed.self, feedExample)
        XCTAssertEqual(f.cursor, "epoch1.9")
        XCTAssertFalse(f.more)
        let e = try XCTUnwrap(f.entries.first)
        XCTAssertEqual(e.titleId, "anime:5114")
        XCTAssertEqual(e.rev, 9)
        XCTAssertEqual(e.entry.score, 90)
        XCTAssertEqual(e.entry.started, "2026-11-03")
        XCTAssertNil(e.entry.finished)
        XCTAssertEqual(f.removed.first?.titleId, "tv:1399")
        let list = try XCTUnwrap(f.lists.changed.first)
        XCTAssertEqual(list.list.name, "Cozy picks")
        XCTAssertEqual(list.position, 0)
        XCTAssertEqual(list.rev, 7)
        XCTAssertEqual(list.list.level.profile.visibility, .friends)
        XCTAssertEqual(list.list.items.first?.mine, .current)
        XCTAssertEqual(f.lists.removed.first?.id, 5)

        // the app's view of it
        let lib = e.library
        XCTAssertEqual(lib.id, "anime:5114")
        XCTAssertEqual(lib.status, .current)
        XCTAssertEqual(lib.progress, 3)

        // an entry goes back out with the website's keys (nulls included)
        let back = try json(APIClient.encoder.encode(e.entry))
        guard case .object(let doc) = try json(feedExample), case .array(let entries)? = doc["entries"],
              case .object(let first)? = entries.first, let docEntry = first["entry"] else { return XCTFail() }
        XCTAssertEqual(back, docEntry)
    }

    func testFeedQuery() async throws {
        let t = StubTransport()
        t.reply(#"{"entries":[],"removed":[],"lists":{"changed":[],"removed":[]},"cursor":"epoch1.9","more":false,"serverTime":1}"#)
        let api = APIClient(transport: t, token: token)
        _ = try await api.libraryChanges(since: nil)
        _ = try await api.libraryChanges(since: "epoch1.9", limit: 9999)
        XCTAssertEqual(t.sent[0].url(on: base)?.absoluteString, "https://guptrack.example.ts.net/api/app/v1/library/changes")
        XCTAssertEqual(t.sent[1].url(on: base)?.absoluteString,
                       "https://guptrack.example.ts.net/api/app/v1/library/changes?since=epoch1.9&limit=500")
    }

    // MARK: §7.2 the outbox

    func testWriteBody() throws {
        let meta = TitleMeta(title: "Fullmetal Alchemist: Brotherhood", cover: "https://s4.anilist.co/c.jpg", format: "TV",
                             total: 64, minutes: 24)
        let ops = WriteBatch(ops: [
            WriteOp(requestId: "op-1", op: .status, media: .anime, id: "5114", at: 1_793_724_170_991, status: .current, meta: meta),
            WriteOp(requestId: "op-2", op: .progress, media: .anime, id: "5114", at: 1_793_724_170_995, progress: 3),
            WriteOp(requestId: "op-3", op: .score, media: .anime, id: "5114", at: 1_793_724_170_998, score: 90),
            WriteOp(requestId: "op-4", op: .edit, media: .anime, id: "5114", at: 1_793_724_171_002, entry: ["notes": .string("so good")]),
            WriteOp(requestId: "op-5", op: .score, media: .anime, id: "5114", at: 1_793_724_171_003),
        ])
        let doc = try json(#"""
        { "ops": [
          { "requestId": "op-1", "op": "status", "media": "anime", "id": "5114", "status": "current", "at": 1793724170991,
            "meta": { "title": "Fullmetal Alchemist: Brotherhood", "cover": "https://s4.anilist.co/c.jpg", "format": "TV", "total": 64, "minutes": 24 } },
          { "requestId": "op-2", "op": "progress", "media": "anime", "id": "5114", "progress": 3, "at": 1793724170995 },
          { "requestId": "op-3", "op": "score", "media": "anime", "id": "5114", "score": 90, "at": 1793724170998 },
          { "requestId": "op-4", "op": "edit", "media": "anime", "id": "5114", "entry": { "notes": "so good" }, "at": 1793724171002 },
          { "requestId": "op-5", "op": "score", "media": "anime", "id": "5114", "score": null, "at": 1793724171003 }
        ] }
        """#)
        XCTAssertEqual(try json(APIClient.encoder.encode(ops)), doc)
    }

    func testWriteCall() async throws {
        let t = StubTransport()
        t.reply(#"""
        {
          "results": [
            { "requestId": "op-1", "applied": true, "media": "anime", "id": "5114",
              "entry": { "media": "anime", "entry": { "id": "5114", "title": "Fullmetal Alchemist: Brotherhood", "alt": [],
                         "cover": "", "format": "TV", "status": "current", "progress": 3, "total": 64, "score": null,
                         "minutes": 24, "updated": 0, "position": 0, "readVolumes": 0, "repeats": 0, "rewatch": null,
                         "started": null, "finished": null, "notes": "", "favourite": false, "idMal": null, "added": 1 },
                         "statusAt": 1, "progressAt": 1, "scoreAt": 0, "changedAt": 1, "rev": 10 } },
            { "requestId": "op-2", "applied": false, "reason": "stale", "media": "anime", "id": "5114", "entry": null },
            { "requestId": "op-6", "applied": true, "media": "tv", "id": "1399", "entry": null, "removed": true },
            { "requestId": "op-5", "applied": false, "error": "bad_request", "message": "Bad status" }
          ],
          "cursor": "epoch1.12",
          "serverTime": 1793724171075
        }
        """#)
        let op = WriteOp(requestId: "op-1", op: .progress, media: .anime, id: "5114", at: 1, progress: 3)
        let a = try await APIClient(transport: t, token: token).writeLibrary(WriteBatch(ops: [op]))
        XCTAssertEqual(t.sent[0].method, "POST")
        XCTAssertEqual(t.sent[0].path, "library/write")
        XCTAssertNil(t.sent[0].requestId, "the ops carry their ids in the body")
        XCTAssertEqual(a.cursor, "epoch1.12")
        XCTAssertEqual(a.results.map(\.requestId), ["op-1", "op-2", "op-6", "op-5"])
        XCTAssertEqual(a.results[0].entry?.rev, 10)
        XCTAssertEqual(a.results[1].reason, "stale")
        XCTAssertEqual(a.results[2].removed, true)
        XCTAssertNil(a.results[3].media)
        XCTAssertEqual(a.results[3].message, "Bad status")
    }

    /// newer wins: the demo server keeps the doc's rule, so the app's handling of `stale` is tested against it
    func testNewerWins() throws {
        let server = DemoLibrary()
        let feed = try XCTUnwrap(server.changes(since: nil, limit: 500))
        let e = try XCTUnwrap(feed.entries.first)
        let old = WriteOp(requestId: "old", op: .progress, media: e.media, id: e.entry.id, at: e.progressAt - 1,
                          progress: e.entry.progress + 1)
        let new = WriteOp(requestId: "new", op: .progress, media: e.media, id: e.entry.id, at: e.progressAt + 1,
                          progress: e.entry.progress + 1)
        let a = server.write(WriteBatch(ops: [old, new]))
        XCTAssertEqual(a.results.map(\.applied), [false, true])
        XCTAssertEqual(a.results[0].reason, "stale")
        XCTAssertEqual(a.results[1].entry?.entry.progress, e.entry.progress + 1)
        XCTAssertGreaterThan(a.results[1].entry?.rev ?? 0, e.rev)
        // what changed after the old cursor is just that entry
        let after = try XCTUnwrap(server.changes(since: feed.cursor, limit: 500))
        XCTAssertEqual(after.entries.map(\.titleId), [e.titleId])
        XCTAssertNil(server.changes(since: "another-epoch.3", limit: 10), "a cursor from another server is expired")
    }

    // MARK: media names

    func testMediaNames() throws {
        XCTAssertEqual(APIMedia.allCases.map(\.rawValue), ["anime", "manga", "tv", "movies", "books"])
        XCTAssertEqual(MediaKind.movie.api, .movies)
        XCTAssertEqual(TitleKey(titleId: "movie:603")?.media, .movies)
        XCTAssertEqual(TitleKey(titleId: "movies:603")?.titleId, "movie:603")
        XCTAssertEqual(TitleKey(titleId: "book:OL45804W")?.media, .books)
        XCTAssertNil(TitleKey(titleId: "comics:1"))
    }
}
