import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
#if canImport(Security)
import Security
#endif

// What the app shares with its widgets and its share extension through the App Group (group.app.guptrack.phone).
// Plain Foundation: the app and both extensions compile this file, and so do the Linux tests (with a folder of
// their own instead of the App Group's).
//
//   state.json    the app writes it whenever the library changes, the Home page reads home/live, or you sign in or
//                 out: the library as it shows (pending changes included), the next episodes and the server's
//                 address. The widgets draw from it; the share extension matches links against it.
//   outbox.json   a widget's +1 or the share sheet's Add, kept until the app takes them (when it next comes to the
//                 front) and sends them like any change made in the app. Locked while read or written, as the
//                 extensions run in their own processes.
//
// The token stays in the Keychain, in the App Group's access group (KeychainTokenStore), so the share extension can
// ask the server about a link the shared library doesn't know (SharedServer).
//
// Without the App Group (an unsigned simulator build, Linux) there is no shared folder: the extensions fall back to
// the demo they bundle, and the app shares nothing.

enum AppGroup {
    static let id = "group.app.guptrack.phone"

    /// the shared folder; nil without the entitlement
    static var folder: URL? {
        #if os(iOS) || os(macOS)
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
        #else
        return nil
        #endif
    }
}

/// What the extensions know of the app, as the app last wrote it.
struct SharedState: Codable, Equatable, Sendable {
    var made: Date
    var signedIn: Bool
    /// the app runs the demo (-demo): its clock and data
    var demo: Bool
    /// the server the app is signed in to (pictures that live on it, "/media/…", are fetched there)
    var server: URL?
    var library: [LibraryEntry]
    var catalog: ExtensionCatalog

    static func signedOut(now: Date) -> SharedState {
        SharedState(made: now, signedIn: false, demo: false, server: nil, library: [], catalog: ExtensionCatalog())
    }
}

/// The App Group's files (or a test folder).
final class SharedBox: @unchecked Sendable {
    let folder: URL

    init(folder: URL) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// the App Group's box; nil without it
    static var app: SharedBox? { AppGroup.folder.map { SharedBox(folder: $0.appendingPathComponent("shared")) } }

    private var stateURL: URL { folder.appendingPathComponent("state.json") }
    private var outboxURL: URL { folder.appendingPathComponent("outbox.json") }
    private var lockPath: String { folder.appendingPathComponent("outbox.lock").path }

    // MARK: the app's state

    func write(_ state: SharedState) {
        guard let data = try? ExtensionsJSON.encoder.encode(state) else { return }
        try? data.write(to: stateURL, options: [.atomic])
    }

    /// nil when the app hasn't written it yet
    func read() -> SharedState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? ExtensionsJSON.decoder.decode(SharedState.self, from: data)
    }

    // MARK: the extensions' changes

    /// the changes waiting for the app, in order
    func pending() -> [WidgetOutbox.Change] {
        locked { loadOutbox().changes }
    }

    func append(_ change: WidgetOutbox.Change) {
        locked {
            var box = loadOutbox()
            box.changes.append(change)
            saveOutbox(box)
        }
    }

    /// the app takes every waiting change (and the box is empty after)
    func take() -> [WidgetOutbox.Change] {
        locked {
            let box = loadOutbox()
            if !box.changes.isEmpty { saveOutbox(WidgetOutbox()) }
            return box.changes
        }
    }

    /// a widget's +1 on a title as it stands with the waiting changes; returns the entry after it (nil when nothing
    /// changed)
    @discardableResult
    func step(_ id: String, in library: [LibraryEntry], now: Date) -> LibraryEntry? {
        locked {
            var box = loadOutbox()
            let after = box.step(id, in: library, now: now)
            if after != nil { saveOutbox(box) }
            return after
        }
    }

    /// signed out: nothing of the account stays behind
    func clear() {
        locked { try? FileManager.default.removeItem(at: outboxURL) }
        write(.signedOut(now: Clock.now))
    }

    private func loadOutbox() -> WidgetOutbox {
        guard let data = try? Data(contentsOf: outboxURL),
              let box = try? ExtensionsJSON.decoder.decode(WidgetOutbox.self, from: data) else { return WidgetOutbox() }
        return box
    }

    private func saveOutbox(_ box: WidgetOutbox) {
        guard let data = try? ExtensionsJSON.encoder.encode(box) else { return }
        try? data.write(to: outboxURL, options: [.atomic])
    }

    /// runs `work` holding the box's lock (flock: the app and the extensions are separate processes)
    private func locked<T>(_ work: () -> T) -> T {
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return work() }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        return work()
    }
}

/// What the widgets and the share extension draw from: the app's shared library with the changes still waiting in
/// the box on top, or (without the App Group: unsigned simulator builds, the screen tests) the demo they bundle.
struct ExtensionSource: Equatable, Sendable {
    var library: [LibraryEntry]
    var catalog: ExtensionCatalog
    /// runs on the demo's clock and data
    var demo: Bool
    var signedIn: Bool
    /// where the extensions' changes go: the App Group's box, nil for the bundled demo
    var usesBox: Bool

    static func current(_ box: SharedBox?, bundled: () -> (library: [LibraryEntry], catalog: ExtensionCatalog))
        -> ExtensionSource {
        guard let box else {
            let b = bundled()
            return ExtensionSource(library: b.library, catalog: b.catalog, demo: true, signedIn: true, usesBox: false)
        }
        // the app hasn't run yet: nothing to show until it's signed in
        guard let state = box.read(), state.signedIn else {
            return ExtensionSource(library: [], catalog: ExtensionCatalog(), demo: false, signedIn: false, usesBox: true)
        }
        let library = WidgetOutbox(changes: box.pending()).apply(to: state.library)
        var catalog = state.catalog
        if state.demo {
            // the demo app's catalogue (titles to match, seasons) is the bundled one; its next episodes are the app's
            catalog = bundled().catalog
            if !state.catalog.upcoming.isEmpty { catalog.upcoming = state.catalog.upcoming }
        }
        return ExtensionSource(library: library, catalog: catalog, demo: state.demo, signedIn: true, usesBox: true)
    }

    /// the library as the app wrote it, before the waiting changes (what a +1 is worked out from)
    static func base(_ box: SharedBox) -> [LibraryEntry] { box.read()?.library ?? [] }
}

/// The signed-in server and token as the extensions read them from the shared Keychain item (the app's
/// KeychainTokenStore writes it; only the two fields they need are read here).
struct SharedAccount: Decodable, Equatable, Sendable {
    var baseURL: URL
    var token: String

    #if canImport(Security)
    static func load() -> SharedAccount? {
        guard let data = KeychainItem.load() else { return nil }
        return try? JSONDecoder().decode(SharedAccount.self, from: data)
    }
    #endif

    /// a picture's address: catalogue covers as they are, GupTrack's own ("/media/…") on this server's files
    /// endpoint, with the token
    func request(for picture: URL) -> URLRequest {
        guard picture.scheme == nil, picture.path.hasPrefix("/") else { return URLRequest(url: picture) }
        var r = URLRequest(url: URL(string: baseURL.absoluteString.trimmingSuffix("/") + "/api/app/v1/files" + picture.absoluteString)
            ?? picture)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }
}

extension String {
    func trimmingSuffix(_ s: String) -> String { hasSuffix(s) ? String(dropLast(s.count)) : self }
}

#if canImport(Security)
/// The Keychain item holding the account: this device only, readable after the first unlock (a widget refreshes
/// while the phone is locked), in the App Group's access group so the extensions can read it. Without the App
/// Group's entitlement (an unsigned simulator build) the group is left out and the item is the app's own.
enum KeychainItem {
    static let service = "app.guptrack.phone.account"
    static let account = "server"
    private static let missingEntitlement: OSStatus = -34018

    private static func query(_ service: String, group: Bool) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecAttrSynchronizable as String: false]
        if group { q[kSecAttrAccessGroup as String] = AppGroup.id }
        return q
    }

    /// runs a Keychain call in the group, and again without it when the build has no App Group
    private static func call(_ service: String, _ work: ([String: Any]) -> OSStatus) -> OSStatus {
        let status = work(query(service, group: true))
        return status == missingEntitlement ? work(query(service, group: false)) : status
    }

    static func load(service: String = service) -> Data? {
        var out: CFTypeRef?
        let status = call(service) { q in
            var q = q
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            return SecItemCopyMatching(q as CFDictionary, &out)
        }
        return status == errSecSuccess ? out as? Data : nil
    }

    @discardableResult
    static func save(_ data: Data, service: String = service) -> Bool {
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = call(service) { q in
            var s = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
            if s == errSecItemNotFound { s = SecItemAdd(q.merging(attrs) { $1 } as CFDictionary, nil) }
            return s
        }
        return status == errSecSuccess
    }

    static func delete(service: String = service) {
        _ = call(service) { SecItemDelete($0 as CFDictionary) }
    }
}
#endif

/// The share extension's questions for the server, for a link the shared library doesn't know: which title it
/// names (GET resolve?url=…, docs/app-api.md §8.4), then that title (GET titles/:kind/:id §8.3).
struct SharedServer: Sendable {
    let account: SharedAccount
    var session: URLSession = .shared

    private struct Resolved: Decodable { var title: TitleRef? }

    private struct Lookup: Decodable {
        struct Detail: Decodable {
            var ref: TitleRef
            var title: String
            var alt: [String]?
            var cover: String?
            var format: String?
            var year: Int?
            var count: Int?
            var volumes: Int?
        }

        var title: Detail
    }

    private func get<T: Decodable>(_ endpoint: String, _ query: [URLQueryItem] = []) async -> T? {
        guard var c = URLComponents(string: account.baseURL.absoluteString.trimmingSuffix("/") + "/api/app/v1/" + endpoint)
        else { return nil }
        if !query.isEmpty { c.queryItems = query }
        guard let url = c.url else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 10)
        r.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, res) = try? await session.data(for: r), (res as? HTTPURLResponse)?.statusCode == 200 else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// the title a shared link names, nil when GupTrack doesn't know it (or the server can't be reached)
    func title(for link: String) async -> Title? {
        guard let resolved: Resolved = await get("resolve", [URLQueryItem(name: "url", value: link)]),
              let ref = resolved.title,
              let found: Lookup = await get("titles/\(ref.kind.rawValue)/\(ref.id)") else { return nil }
        let d = found.title
        let alt = (d.alt ?? []).filter { !$0.isEmpty }
        return Title(id: d.ref.titleId, media: d.ref.kind, name: d.title,
                     subtitle: alt.isEmpty ? nil : alt.joined(separator: " · "),
                     cover: d.cover.flatMap { URL(string: $0) },
                     format: d.format.flatMap { $0.isEmpty ? nil : $0 }, year: d.year, total: d.count,
                     volumes: d.volumes)
    }
}
