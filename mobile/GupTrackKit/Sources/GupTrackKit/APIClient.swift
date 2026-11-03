import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// How the app reaches GupTrack's app API (/api/app/v1 on the server): one request in, its body and status out.
/// `LiveTransport` talks HTTPS; `DemoTransport` (Demo.swift) answers from the recorded fixtures, so the demo and the
/// tests go through the same decoding as the real app.
protocol Transport: AnyObject, Sendable {
    func send(_ request: APIRequest) async throws -> (Data, Int)
}

/// One call to the app API. `path` is relative to /api/app/v1 ("library/changes", "titles/anime/210482").
struct APIRequest: Equatable, Sendable {
    var method: String
    var path: String
    var query: [URLQueryItem]
    var body: Data?
    var token: String?

    init(_ method: String = "GET", _ path: String, query: [URLQueryItem] = [], body: Data? = nil, token: String? = nil) {
        self.method = method
        self.path = path.hasPrefix("/") ? String(path.dropFirst()) : path
        self.query = query
        self.body = body
        self.token = token
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
    case signedOut              // 401: the server doesn't know this device's token (anymore)
    case unreachable(String)    // no answer: Tailscale off, the PC asleep, offline
    case server(Int, String)    // the server answered with an error
    case unreadable             // an answer this app can't read (app or server out of date)

    var message: String {
        switch self {
        case .signedOut: return "Your GupTrack server signed this iPhone out. Sign in again."
        case .unreachable(let why): return why
        case .server(_, let text): return text
        case .unreadable: return "GupTrack sent something this app can't read. Update the app or the server."
        }
    }

    var isUnreachable: Bool {
        if case .unreachable = self { return true }
        return false
    }
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
        if let body = r.body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    func send(_ r: APIRequest) async throws -> (Data, Int) {
        let req = try Self.makeRequest(r, base: base)
        do {
            let (data, response) = try await session.data(for: req)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
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

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// The app API client: typed calls over a transport. Dates are ISO 8601 both ways.
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
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(ISO8601.string(date))
        }
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await call(APIRequest("GET", path, query: query, token: token))
    }

    func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, _ body: B) async throws -> T {
        try await call(APIRequest(method, path, body: try Self.encoder.encode(body), token: token))
    }

    func send<T: Decodable>(_ method: String, _ path: String) async throws -> T {
        try await call(APIRequest(method, path, token: token))
    }

    func call<T: Decodable>(_ r: APIRequest) async throws -> T {
        let (data, status) = try await transport.send(r)
        if status == 401 && r.token != nil { throw APIError.signedOut }
        guard (200..<300).contains(status) else {
            let text = (try? Self.decoder.decode(ErrorBody.self, from: data))?.error
            throw APIError.server(status, text ?? "GupTrack answered with an error (\(status)).")
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.unreadable
        }
    }
}

private struct ErrorBody: Decodable {
    var error: String?
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
