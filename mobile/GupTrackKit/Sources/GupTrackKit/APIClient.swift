import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// How the app reaches GupTrack's app API (/api/app/v1 on the server): one request in, its body and status out.
/// `LiveTransport` talks HTTPS; `DemoTransport` (Demo.swift) answers from the recorded fixtures, so the demo and the
/// tests go through the same decoding as the real app.
protocol Transport: AnyObject, Sendable {
    func send(_ request: APIRequest) async throws -> APIResponse
    /// a long answer read line by line as it comes (GET messages/events, server-sent events)
    func lines(_ request: APIRequest) -> AsyncThrowingStream<String, Error>
}

extension Transport {
    /// no live stream (the demo): the app asks messages/pulse instead
    func lines(_ request: APIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: APIError.server(404, "unknown_endpoint", "No live updates here.")) }
    }
}

/// What came back: the body, the HTTP status and the headers the client reads (Retry-After, x-request-replayed).
struct APIResponse: Equatable, Sendable {
    var data: Data
    var status: Int
    var headers: [String: String]

    init(_ data: Data, _ status: Int, headers: [String: String] = [:]) {
        self.data = data
        self.status = status
        self.headers = headers
    }

    /// a header by name, any case
    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// One call to the app API. `path` is relative to /api/app/v1 ("library/changes", "titles/anime/210482").
struct APIRequest: Equatable, Sendable {
    var method: String
    var path: String
    var query: [URLQueryItem]
    var body: Data?
    var token: String?
    /// X-Request-Id (§2): the same id again gets the first answer again, nothing done twice
    var requestId: String?
    /// the body's type; JSON unless it's an upload's raw bytes
    var contentType: String

    init(_ method: String = "GET", _ path: String, query: [URLQueryItem] = [], body: Data? = nil, token: String? = nil,
         requestId: String? = nil, contentType: String = "application/json") {
        self.method = method
        self.path = path.hasPrefix("/") ? String(path.dropFirst()) : path
        self.query = query
        self.body = body
        self.token = token
        self.requestId = requestId
        self.contentType = contentType
    }

    /// A write that may carry X-Request-Id: every POST, PUT, PATCH and DELETE but the signed-out calls (§4) and the
    /// ones whose answer holds a secret, which the server never keeps.
    static func takesRequestId(_ method: String, _ path: String) -> Bool {
        guard ["POST", "PUT", "PATCH", "DELETE"].contains(method) else { return false }
        let p = path.hasPrefix("/") ? String(path.dropFirst()) : path
        if p.hasPrefix("auth/") && p != "auth/sign-out" { return false }
        return !["account/password", "account/recovery-codes", "devices/pairing", "accounts/invites"].contains(p)
    }

    /// the full URL on a server: <base>/api/app/v1/<path>?<query>
    func url(on base: URL) -> URL? {
        guard var c = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        let root = c.path.hasSuffix("/") ? String(c.path.dropLast()) : c.path
        c.path = root + AppAPI.prefix + "/" + path
        c.queryItems = query.isEmpty ? nil : query
        return c.url
    }
}

enum APIError: Error, Equatable {
    case signedOut              // 401 unauthorized: the server doesn't know this phone's token (anymore)
    case unreachable(String)    // no answer: Tailscale off, the PC asleep, offline
    case server(ServerError)    // the server answered with an error (§3)
    case unreadable             // an answer this app can't read (app or server out of date)

    /// an error answer: status, code and the message written for people
    static func server(_ status: Int, _ code: String, _ message: String, retryAfter: Int? = nil) -> APIError {
        .server(ServerError(status: status, code: code, message: message, retryAfter: retryAfter))
    }

    var message: String {
        switch self {
        case .signedOut: return "Your GupTrack server signed this iPhone out. Sign in again."
        case .unreachable(let why): return why
        case .server(let e): return e.message
        case .unreadable: return "GupTrack sent something this app can't read. Update the app or the server."
        }
    }

    /// the error's code (`not_found`, `cursor_expired`…); nil when the server didn't answer
    var code: String? {
        switch self {
        case .signedOut: return "unauthorized"
        case .server(let e): return e.code
        default: return nil
        }
    }

    var status: Int? {
        if case .server(let e) = self { return e.status }
        return nil
    }

    var isUnreachable: Bool {
        if case .unreachable = self { return true }
        return false
    }

    /// worth sending again later: no answer, 429, 5xx (§7.2)
    var isRetryable: Bool {
        switch self {
        case .unreachable: return true
        case .server(let e): return e.status == 429 || e.status >= 500
        default: return false
        }
    }
}

/// An error answer (§3): `{ "error": "not_found", "message": "That account isn’t here.", "serverTime": … }`.
struct ServerError: Equatable, Sendable {
    var status: Int
    /// bad_request, unauthorized, wrong_password, bad_code, forbidden, not_found, unknown_endpoint,
    /// method_not_allowed, cursor_expired, conflict, too_large, rate_limited, upstream_unavailable,
    /// catalogue_unavailable, server_error
    var code: String
    var message: String
    /// 429: seconds to wait (Retry-After)
    var retryAfter: Int?
}

/// HTTPS to the GupTrack server: an ephemeral session (no cookies, cache or stored credentials), no redirects, the
/// device token as a bearer token. The same rules as GupWorks' phone client.
final class LiveTransport: Transport, @unchecked Sendable {
    let base: URL
    private let session: URLSession

    init(base: URL, timeout: TimeInterval = 15) {
        self.base = base
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        #if canImport(Darwin)
        c.waitsForConnectivity = false
        #endif
        c.httpCookieStorage = nil
        c.httpCookieAcceptPolicy = .never
        c.urlCache = nil
        c.urlCredentialStorage = nil
        session = URLSession(configuration: c, delegate: NoRedirects(), delegateQueue: nil)
    }

    static func makeRequest(_ r: APIRequest, base: URL) throws -> URLRequest {
        guard let url = r.url(on: base) else { throw APIError.unreachable("That server address isn't valid.") }
        var req = URLRequest(url: url)
        req.httpMethod = r.method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = r.token { req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let id = r.requestId { req.setValue(id, forHTTPHeaderField: "X-Request-Id") }
        if let body = r.body {
            req.setValue(r.contentType, forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    func send(_ r: APIRequest) async throws -> APIResponse {
        let req = try Self.makeRequest(r, base: base)
        do {
            let (data, response) = try await session.data(for: req)
            let http = response as? HTTPURLResponse
            var headers: [String: String] = [:]
            for (k, v) in http?.allHeaderFields ?? [:] {
                if let k = k as? String, let v = v as? String { headers[k.lowercased()] = v }
            }
            return APIResponse(data, http?.statusCode ?? 0, headers: headers)
        } catch {
            throw APIError.unreachable(Self.why(error))
        }
    }

    static func why(_ error: Error) -> String {
        guard let e = error as? URLError else { return "Can't reach your GupTrack server." }
        switch e.code {
        case .notConnectedToInternet, .dataNotAllowed: return "This iPhone is offline."
        case .timedOut: return "Your GupTrack server didn't answer. Is the PC awake and Tailscale on?"
        case .cannotFindHost, .dnsLookupFailed:
            return "Can't find your GupTrack server. In the Tailscale app, check that Use Tailscale DNS is on."
        case .cannotConnectToHost: return "Your GupTrack server turned the connection down. Is GupTrack running?"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            return "The secure connection to your server failed. Check the iPhone's date and time."
        case .cancelled: return "Stopped before the server answered."
        default: return "Can't reach your GupTrack server (error \(e.code.rawValue))."
        }
    }
}

extension LiveTransport {
    /// The answer line by line as it arrives, on a session of its own: no time limit overall, but 30 s without a byte
    /// counts as gone (the server sends a beat every 10 s). An error status ends it with that error (401 signed out,
    /// 429 too many streams); stopping the stream (its task cancelled) closes the connection.
    func lines(_ r: APIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            guard var req = try? Self.makeRequest(r, base: base) else {
                cont.finish(throwing: APIError.unreachable("That server address isn't valid."))
                return
            }
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 30
            let c = URLSessionConfiguration.ephemeral
            c.timeoutIntervalForRequest = 30
            c.timeoutIntervalForResource = 7 * 24 * 3600
            c.httpCookieStorage = nil
            c.httpCookieAcceptPolicy = .never
            c.urlCache = nil
            c.urlCredentialStorage = nil
            let reader = LineReader(cont, signedIn: r.token != nil)
            let session = URLSession(configuration: c, delegate: reader, delegateQueue: nil)
            let task = session.dataTask(with: req)
            cont.onTermination = { _ in task.cancel() }
            task.resume()
        }
    }
}

/// Splits a streamed answer into lines for `LiveTransport.lines`.
private final class LineReader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let cont: AsyncThrowingStream<String, Error>.Continuation
    private let signedIn: Bool
    private let lock = NSLock()
    private var status = 0
    private var buffer: [UInt8] = []
    private var errorBody = Data()

    init(_ cont: AsyncThrowingStream<String, Error>.Continuation, signedIn: Bool) {
        self.cont = cont
        self.signedIn = signedIn
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.withLock { status = (response as? HTTPURLResponse)?.statusCode ?? 0 }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let lines: [String] = lock.withLock {
            guard status == 200 else { errorBody.append(data); return [] }
            buffer.append(contentsOf: data)
            var out: [String] = []
            while let i = buffer.firstIndex(of: 0x0A) {
                out.append(String(decoding: buffer[..<i], as: UTF8.self))
                buffer.removeSubrange(...i)
            }
            return out
        }
        for l in lines { cont.yield(l) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (status, body) = lock.withLock { (self.status, errorBody) }
        if status != 0 && status != 200 {
            do {
                try APIClient.check(APIResponse(body, status), signedIn: signedIn)
                cont.finish(throwing: APIError.unreadable)
            } catch {
                cont.finish(throwing: error)
            }
        } else if let error {
            cont.finish(throwing: APIError.unreachable(LiveTransport.why(error)))
        } else {
            cont.finish()
        }
        session.finishTasksAndInvalidate()
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// The app API client: typed calls over a transport. Times are ms since 1970 both ways (§2); a write carries a new
/// X-Request-Id unless the caller passes the one it keeps with the action.
final class APIClient: @unchecked Sendable {
    let transport: Transport
    var token: String?

    init(transport: Transport, token: String? = nil) {
        self.transport = transport
        self.token = token
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            if let n = try? c.decode(Double.self) { return Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n) }
            let s = try c.decode(String.self)
            if let d = ISO8601.parse(s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a date: \(s)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await call(APIRequest("GET", path, query: query, token: token))
    }

    func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, _ body: B, query: [URLQueryItem] = [],
                                          requestId: String? = nil) async throws -> T {
        try await call(APIRequest(method, path, query: query, body: try Self.encoder.encode(body), token: token,
                                  requestId: Self.requestId(method, path, requestId)))
    }

    func send<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [],
                            requestId: String? = nil) async throws -> T {
        try await call(APIRequest(method, path, query: query, token: token,
                                  requestId: Self.requestId(method, path, requestId)))
    }

    /// an upload: the raw file as the body, with its type (§5)
    func upload<T: Decodable>(_ path: String, _ data: Data, contentType: String, requestId: String? = nil) async throws -> T {
        try await call(APIRequest("POST", path, body: data, token: token,
                                  requestId: Self.requestId("POST", path, requestId), contentType: contentType))
    }

    static func requestId(_ method: String, _ path: String, _ given: String?) -> String? {
        APIRequest.takesRequestId(method, path) ? (given ?? UUID().uuidString) : nil
    }

    func call<T: Decodable>(_ r: APIRequest) async throws -> T {
        let answer = try await transport.send(r)
        try Self.check(answer, signedIn: r.token != nil)
        do {
            return try Self.decoder.decode(T.self, from: answer.data)
        } catch {
            throw APIError.unreadable
        }
    }

    /// an error answer as an APIError; a 401 `unauthorized` with a token means this phone was signed out
    static func check(_ answer: APIResponse, signedIn: Bool) throws {
        guard !(200..<300).contains(answer.status) else { return }
        let body = try? decoder.decode(ErrorBody.self, from: answer.data)
        let code = body?.error ?? (answer.status == 401 ? "unauthorized" : "server_error")
        if answer.status == 401 && signedIn && code == "unauthorized" { throw APIError.signedOut }
        let retry = answer.header("Retry-After").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        throw APIError.server(answer.status, code, body?.message ?? "GupTrack answered with an error (\(answer.status)).",
                              retryAfter: retry)
    }
}

private struct ErrorBody: Decodable {
    var error: String?
    var message: String?
    var serverTime: Int64?
}

struct OKReply: Codable, Equatable, Sendable {
    var ok: Bool
}

/// ISO 8601 with or without fractional seconds.
enum ISO8601 {
    static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withFullDate]
        return f.date(from: s)
    }

    static func string(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }
}
