import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// The demo fixtures are real answers in the app API's shape: every file must be JSON, and the shared ones must
/// decode. Each screen group's own fixtures are decoded by that group's tests.
final class FixtureTests: XCTestCase {
    func testEveryFixtureIsJSON() throws {
        let api = Demo.root.appendingPathComponent("api")
        let files = FileManager.default.enumerator(at: api, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "json" } ?? []
        XCTAssertGreaterThan(files.count, 3, "no fixtures under \(api.path)")
        for f in files {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(contentsOf: f)), f.lastPathComponent)
        }
    }

    func testSharedFixturesDecode() throws {
        let lib = Demo.library()
        XCTAssertEqual(Set(lib.map(\.media)), Set(MediaKind.allCases))
        XCTAssertEqual(Set(lib.map(\.id)).count, lib.count, "a title is on the list twice")
        for e in lib {
            XCTAssertTrue(e.id.hasPrefix(e.media.rawValue + ":"), e.id)
            if let total = e.title.total { XCTAssertLessThanOrEqual(e.progress, total, e.id) }
            XCTAssertNotNil(e.title.cover, "\(e.id) has no cover")
        }
        XCTAssertEqual(try Demo.load(MeAnswer.self, "api/me.json").me.username, "mika")
        XCTAssertEqual(try Demo.load(ServerInfo.self, "api/server.json").api, AppAPI.version)
        let lists = try Demo.load(ListWire.Yours.self, "api/lists.json").lists
        for l in lists { _ = try Demo.load(MyList.self, "api/lists/\(l.slug).json") }
    }

    /// The public build copy only ever loads art from the catalogue CDNs at runtime.
    func testLinksGoOnlyToThePublicCatalogues() throws {
        // the catalogues' picture CDNs, plus their own title pages (a title's links) and trailers
        let hosts: Set<String> = ["s4.anilist.co", "image.tmdb.org", "covers.openlibrary.org", "anilist.co",
                                  "myanimelist.net", "www.themoviedb.org", "openlibrary.org", "www.youtube.com"]
        let api = Demo.root.appendingPathComponent("api")
        let files = FileManager.default.enumerator(at: api, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "json" } ?? []
        let pattern = try NSRegularExpression(pattern: #"https?://([^/"]+)"#)
        for f in files {
            let s = try String(contentsOf: f, encoding: .utf8)
            for m in pattern.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                let host = String(s[Range(m.range(at: 1), in: s)!])
                if host.hasSuffix(".example") || host == "guptrack.example" { continue }
                XCTAssertTrue(hosts.contains(host), "\(f.lastPathComponent): \(host)")
            }
        }
    }
}
