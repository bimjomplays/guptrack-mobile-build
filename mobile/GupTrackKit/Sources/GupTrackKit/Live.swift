import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Observation

// While the app is in front (RootView): the live message stream, GET messages/events (docs/app-api.md §11.6), and the
// library's change feed every minute. The stream is news only ("fran sent a message"); the screens reload what it
// names. When it can't open (offline, 429: too many streams) the chat asks messages/pulse every few seconds instead.

/// What the live stream said, for the screens: who is typing, and a counter per person that moves on news about your
/// conversation with them (a chat reloads when its counter moves).
@Observable @MainActor
final class LiveMessages {
    /// the stream is open (else the chat asks messages/pulse)
    var connected = false
    /// who is typing, until when (about 6 s after their last keystroke)
    private(set) var typingUntil: [String: Date] = [:]
    /// moves on news about your conversation with that person
    private(set) var news: [String: Int] = [:]
    /// moves on news about any conversation (the message list reloads)
    private(set) var anyNews = 0

    static let typingFor: TimeInterval = 6

    func version(_ who: String) -> Int { news[who] ?? 0 }

    func isTyping(_ who: String, now: Date = Date()) -> Bool { (typingUntil[who] ?? .distantPast) > now }

    /// one event; true when the unread count may have changed
    @discardableResult
    func apply(_ e: LiveEvent, now: Date = Date()) -> Bool {
        switch e {
        case .message(let who):
            news[who, default: 0] += 1
            anyNews += 1
            typingUntil[who] = nil
            return true
        case .read(let who):
            news[who, default: 0] += 1
            return false
        case .typing(let who):
            typingUntil[who] = now.addingTimeInterval(Self.typingFor)
            return false
        case .change(let who):
            if let who { news[who, default: 0] += 1 }
            anyNews += 1
            return true
        }
    }

    func reset() {
        connected = false
        typingUntil = [:]
        news = [:]
        anyNews = 0
    }
}

extension APIClient {
    /// GET messages/events, line by line
    func liveEvents() -> AsyncThrowingStream<String, Error> {
        transport.lines(APIRequest("GET", "messages/events", token: token))
    }
}

extension AppModel {
    /// in front and signed in: the live stream and the minute-by-minute library sync, until the task is cancelled
    /// (the app goes to the background) or this phone is signed out
    func stayLive(feedEvery: Duration = .seconds(60)) async {
        guard !isDemo, isSignedIn else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.streamMessages() }
            group.addTask { await self.syncEvery(feedEvery) }
        }
        live.connected = false
    }

    private func syncEvery(_ every: Duration) async {
        while !Task.isCancelled && isSignedIn {
            try? await Task.sleep(for: every)
            guard !Task.isCancelled else { return }
            await syncLibrary()
        }
    }

    /// holds GET messages/events open, reconnecting after its `retry` (longer each time it fails, up to a minute)
    func streamMessages(backoff: Duration = .seconds(1), maxWait: Duration = .seconds(60)) async {
        var wait = backoff
        while !Task.isCancelled && isSignedIn {
            var parser = LiveStream()
            do {
                for try await line in api.liveEvents() {
                    if !live.connected {
                        live.connected = true
                        wait = backoff
                    }
                    if let e = parser.feed(line), live.apply(e) { await updateUnread() }
                }
                // closed by the server: a restart, or this phone's token was removed (then the next call is 401)
                live.connected = false
                wait = .milliseconds(parser.retry)
                await updateUnread()
            } catch let e as APIError {
                live.connected = false
                if case .signedOut = e {
                    signedOutByServer(e)
                    return
                }
                // too many streams (429), unreachable, a server error: the chat asks the pulse meanwhile
                wait = min(wait * 2, maxWait)
                if let after = e.retryAfter { wait = max(wait, .seconds(after)) }
            } catch {
                live.connected = false
                wait = min(wait * 2, maxWait)
            }
            try? await Task.sleep(for: wait)
        }
    }

    /// the Social tab's badge, after news
    func updateUnread() async {
        do {
            unreadMessages = SocialSession.applied(try await api.messageList()).unread
        } catch let e as APIError {
            if case .signedOut = e { signedOutByServer(e) }
        } catch {}
    }
}

extension APIError {
    /// 429's Retry-After, in seconds
    var retryAfter: Int? {
        if case .server(let e) = self { return e.retryAfter }
        return nil
    }
}

/// GupTrack's own pictures (`/media/…`, `/dm/photo/…`, docs/app-api.md §5): kept on the phone by address and shown
/// from there at once, then asked again with If-None-Match the first time each launch: 304 keeps the copy, 404 drops it
/// (a block, a deleted message, a privacy change), offline keeps it. The catalogue's covers are kept and never asked
/// again.
enum PictureFetch {
    enum Outcome: Equatable {
        /// show these bytes (and keep them)
        case fresh(Data)
        /// the copy on the phone is still right
        case keep
        /// not allowed or not there anymore: remove the copy
        case drop
    }

    /// the request for a picture; `cached` when there's a copy on the phone to revalidate
    static func request(_ url: URL, authorization: String?, cached: Bool) -> URLRequest {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        if let authorization {
            r.setValue(authorization, forHTTPHeaderField: "Authorization")
            if cached { r.setValue("\"\(url.lastPathComponent)\"", forHTTPHeaderField: "If-None-Match") }
        }
        return r
    }

    /// what to do with the answer (status nil: no answer)
    static func outcome(status: Int?, data: Data?, cached: Bool) -> Outcome {
        switch status {
        case 200?: return data.map { .fresh($0) } ?? (cached ? .keep : .drop)
        case 304?: return cached ? .keep : .drop
        case 401?, 403?, 404?, 410?: return .drop
        default: return cached ? .keep : .drop
        }
    }

    /// whether a copy on the phone is asked again before it's shown: only GupTrack's own
    static func revalidates(authorization: String?) -> Bool { authorization != nil }
}

extension Notification.Name {
    /// this phone was signed out: forget GupTrack's own pictures kept on it
    static let gupTrackSignedOut = Notification.Name("app.guptrack.phone.signed-out")
}
