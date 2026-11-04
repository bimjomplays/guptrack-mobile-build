import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// The pages around titles (28-31), docs/app-api.md §8.3: characters, people, companies and authors decode as
/// src/catalog/detail.ts writes them, the pages read them, and the calls go where the doc says.
final class PeopleTests: XCTestCase {
    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder.decode(T.self, from: Data(json.utf8))
    }

    static let card = #"{ "ref": { "kind": "anime", "id": "21" }, "title": "ONE PIECE", "cover": null, "format": "TV", "year": 1999, "score": 88 }"#

    func testCharacter() throws {
        let a = try decode(CharacterAnswer.self, #"""
        { "character": {
          "id": "40", "name": "Monkey D. Luffy", "native": "モンキー・D・ルフィ", "alt": ["Straw Hat"], "altSpoiler": [],
          "image": "https://img.example/luffy.jpg",
          "facts": [{ "label": "Height", "value": "174 cm" }, { "label": "Gender", "value": "Male" },
                    { "label": "Age", "value": "17-19" }, { "label": "Devil fruit", "value": "Gomu Gomu no Mi (Hito Hito no Mi, Model: Nika)" },
                    { "label": "Birthday", "value": "May 5" }, { "label": "Blood type", "value": "F" }],
          "description": [[{ "text": "Captain of the Straw Hats. " }, { "text": "He is Joy Boy.", "spoiler": true }]],
          "favourites": 35992,
          "appearances": [{ "title": \#(Self.card), "role": "Main" }],
          "voices": [{ "language": "Japanese", "people": [{ "ref": { "to": "person", "source": "anilist", "id": "95075" }, "name": "Mayumi Tanaka", "image": null }] },
                     { "language": "English", "people": [{ "ref": { "to": "person", "source": "anilist", "id": "5" }, "name": "E Voice", "image": null }] }]
        } }
        """#)
        let p = CharacterPage(a.character)
        XCTAssertEqual(p.headline, "Main character · ONE PIECE")
        XCTAssertEqual(p.favourites, 35992)
        XCTAssertEqual(p.facts.map(\.label), ["Height", "Birthday", "Age", "Gender"], "the usual four first, long values left out")
        XCTAssertEqual(p.facts[2].value, "17–19")
        XCTAssertEqual(p.prose.text, "Captain of the Straw Hats.")
        XCTAssertTrue(p.prose.hasSpoilers)
        XCTAssertEqual(p.voices.map(\.name), ["Mayumi Tanaka", "E Voice"])
        XCTAssertEqual(p.voices[0].route, .person("anilist:95075"))
        XCTAssertEqual(p.voices[0].line, "Japanese")
        XCTAssertEqual(p.appearances[0].line, "TV · 1999 · Main")
        XCTAssertEqual(p.appearances[0].title.id, "anime:21")
        XCTAssertEqual(p.total, 1)
    }

    func testPerson() throws {
        let a = try decode(PersonAnswer.self, #"""
        { "person": {
          "ref": { "to": "person", "source": "tmdb", "id": "1190668" }, "name": "Timothée Chalamet", "native": null,
          "alt": [], "image": null, "known": "Acting",
          "facts": [{ "label": "Known for", "value": "Acting" }, { "label": "Born", "value": "Dec 27, 1995 (age 30)" },
                    { "label": "Birthplace", "value": "New York City, New York, USA" }],
          "bio": [[{ "text": "An actor." }]],
          "groups": [
            { "title": "Known for", "items": [{ "title": { "ref": { "kind": "movie", "id": "693134" }, "title": "Dune: Part Two", "cover": null, "format": "Film", "year": 2024 }, "role": "Paul Atreides" }] },
            { "title": "Acting", "items": [
              { "title": { "ref": { "kind": "movie", "id": "438631" }, "title": "Dune", "cover": null, "format": "Film", "year": 2021 }, "role": "Paul Atreides" },
              { "title": { "ref": { "kind": "movie", "id": "693134" }, "title": "Dune: Part Two", "cover": null, "format": "Film", "year": 2024 }, "role": "Paul Atreides" },
              { "title": { "ref": { "kind": "movie", "id": "1" }, "title": "Not out yet", "cover": null, "format": "Film", "year": null }, "role": "" } ] },
            { "title": "Production", "items": [
              { "title": { "ref": { "kind": "movie", "id": "2" }, "title": "A Production", "cover": null, "format": "Film", "year": 2020 }, "role": "Executive Producer" } ] }
          ]
        } }
        """#)
        let p = PersonPage(a.person)
        XCTAssertEqual(p.id, "tmdb:1190668")
        XCTAssertEqual(p.headline, "Acting")
        XCTAssertEqual(p.bornLine, "Born Dec 27, 1995 (age 30) · New York City, New York, USA")
        XCTAssertEqual(p.knownFor.map(\.id), ["movie:693134"])
        XCTAssertEqual(p.groups, ["Acting", "Production"])
        let acting = p.credits(nil)
        XCTAssertEqual(acting.map(\.title.name), ["Not out yet", "Dune: Part Two", "Dune"], "newest first, undated first")
        XCTAssertEqual(acting[1].line, "as Paul Atreides")
        XCTAssertEqual(acting[0].line, "Film")
        XCTAssertEqual(acting[1].route, .title("movie:693134"))
        XCTAssertEqual(p.credits("Production")[0].line, "Executive Producer")
    }

    func testVoiceActorRolesOpenTheCharacter() throws {
        let a = try decode(PersonAnswer.self, #"""
        { "person": {
          "ref": { "to": "person", "source": "anilist", "id": "95075" }, "name": "Mayumi Tanaka", "native": "田中真弓",
          "alt": [], "image": null, "known": "Voice Actor", "facts": [], "bio": [],
          "groups": [{ "title": "Voice roles", "items": [
            { "title": \#(Self.card), "role": "Main · 3 titles", "character": { "ref": { "to": "character", "id": "40" }, "name": "Monkey D. Luffy", "image": null } } ] }]
        } }
        """#)
        let p = PersonPage(a.person)
        XCTAssertEqual(p.id, "anilist:95075")
        XCTAssertNil(p.bornLine)
        XCTAssertTrue(p.knownFor.isEmpty)
        let c = p.credits(nil)[0]
        XCTAssertEqual(c.character?.name, "Monkey D. Luffy")
        XCTAssertEqual(c.line, "ONE PIECE · Main · 3 titles")
        XCTAssertEqual(c.route, .character("40"))
    }

    func testCompany() throws {
        let a = try decode(CompanyAnswer.self, #"""
        { "company": {
          "ref": { "to": "studio", "id": "569" }, "name": "MAPPA", "kind": "Animation studio", "image": null,
          "facts": [{ "label": "Favourites", "value": "52,051" }], "description": [],
          "groups": [
            { "title": "Animation", "titles": [
              { "ref": { "kind": "anime", "id": "127230" }, "title": "Chainsaw Man", "cover": null, "format": "TV", "year": 2022, "score": 85 },
              { "ref": { "kind": "anime", "id": "3" }, "title": "A Film", "cover": null, "format": "Film", "year": 2025 } ] },
            { "title": "Production", "titles": [
              { "ref": { "kind": "anime", "id": "127230" }, "title": "Chainsaw Man", "cover": null, "format": "TV", "year": 2022 },
              { "ref": { "kind": "anime", "id": "4" }, "title": "Undated", "cover": null, "format": "TV", "year": null } ] }
          ]
        } }
        """#)
        let p = StudioPage(a.company)
        XCTAssertEqual(p.id, "studio:569")
        XCTAssertEqual(p.headline, "Animation studio")
        XCTAssertEqual(p.favourites, 52051)
        XCTAssertEqual(p.titles.count, 3, "once each")
        XCTAssertEqual(p.countLine(inLibrary: 1), "3 titles · 1 in your library")
        XCTAssertEqual(p.filters, [.all, .tv, .film])
        XCTAssertEqual(p.years().map(\.label), ["2025", "2022", "TBA"])
        XCTAssertEqual(p.years(.film).map(\.label), ["2025"])
        XCTAssertEqual(p.titles[0].score, 8.5)
    }

    func testAuthor() throws {
        let a = try decode(PersonAnswer.self, #"""
        { "person": {
          "ref": { "to": "author", "id": "OL7234434A" }, "name": "Andy Weir", "native": null, "alt": [], "image": null,
          "known": "Author", "facts": [{ "label": "Born", "value": "16 June 1972" }, { "label": "Works", "value": "48" }],
          "bio": [],
          "groups": [
            { "title": "Most read", "items": [{ "title": { "ref": { "kind": "book", "id": "OL17091839W" }, "title": "The Martian", "cover": null, "format": "Novel", "year": 2011, "score": 82 }, "role": "Novel · 2011" }] },
            { "title": "Books", "items": [
              { "title": { "ref": { "kind": "book", "id": "OL17091839W" }, "title": "The Martian", "cover": null, "format": "Novel", "year": 2011, "score": 82 }, "role": "Novel · 2011" },
              { "title": { "ref": { "kind": "book", "id": "OL21745884W" }, "title": "Project Hail Mary", "cover": null, "format": "Novel", "year": 2021, "score": 90 }, "role": "Novel · 2021" } ] }
          ]
        } }
        """#)
        let p = AuthorPage(a.person, id: "x")
        XCTAssertEqual(p.id, "OL7234434A")
        XCTAssertEqual(p.headline, "Author")
        XCTAssertEqual(p.bornLine, "Born 16 June 1972")
        XCTAssertEqual(p.works, 48)
        XCTAssertEqual(p.books.map(\.id), ["book:OL17091839W", "book:OL21745884W"])
        XCTAssertEqual(p.sorted().map(\.title.name), ["Project Hail Mary", "The Martian"])
        XCTAssertEqual(p.sorted(newestFirst: false).first?.title.name, "The Martian")
        XCTAssertEqual(p.averageRating, "8.6")
        XCTAssertEqual(p.books[1].line, "Novel · 2021")
    }

    func testCallsGoWhereTheDocSays() async throws {
        let t = StubTransport()
        let api = APIClient(transport: t, token: "demo-token")
        t.reply(#"{"character":{"id":"40","name":"L","native":null,"alt":[],"altSpoiler":[],"image":null,"facts":[],"description":[],"favourites":0,"appearances":[],"voices":[]}}"#)
        _ = try await api.characterPage("40")
        let person = #"{"person":{"ref":{"to":"person","source":"tmdb","id":"1"},"name":"P","native":null,"alt":[],"image":null,"known":"","facts":[],"bio":[],"groups":[]}}"#
        t.reply(person)
        _ = try await api.personPage("tmdb:1190668")
        _ = try await api.personPage("anilist:95075")
        _ = try await api.authorPage("OL7234434A")
        t.reply(#"{"company":{"ref":{"to":"network","id":"49"},"name":"HBO","kind":"TV network","image":null,"facts":[],"description":[],"groups":[]}}"#)
        _ = try await api.studioPage("network:49")
        _ = try await api.studioPage("company:41077")
        XCTAssertEqual(t.sent.map(\.path), ["characters/40", "people/tmdb/1190668", "people/anilist/95075",
                                            "authors/OL7234434A", "companies/network/49", "companies/company/41077"])
        XCTAssertTrue(t.sent.allSatisfy { $0.method == "GET" && $0.query.isEmpty && $0.body == nil })
        do {
            _ = try await api.personPage("person:95075")
            XCTFail("an old-style id isn't asked")
        } catch {}
        XCTAssertEqual(t.sent.count, 6)
    }

    func testDemoPagesDecode() throws {
        let c = CharacterPage(try Demo.load(CharacterAnswer.self, "api/characters/40.json").character)
        XCTAssertEqual(c.name, "Monkey D. Luffy")
        XCTAssertTrue(c.voices.contains { $0.name == "Mayumi Tanaka" && $0.route == .person("anilist:95075") })
        XCTAssertTrue(c.appearances.contains { $0.title.id == "anime:21" && $0.line.hasPrefix("TV · 1999") })
        let tanaka = PersonPage(try Demo.load(PersonAnswer.self, "api/people/anilist/95075.json").person)
        XCTAssertTrue(tanaka.credits(nil).contains { $0.character?.name == "Monkey D. Luffy" })
        let tc = PersonPage(try Demo.load(PersonAnswer.self, "api/people/tmdb/1190668.json").person)
        XCTAssertFalse(tc.knownFor.isEmpty)
        let mappa = StudioPage(try Demo.load(CompanyAnswer.self, "api/companies/studio/569.json").company)
        XCTAssertEqual(mappa.headline.hasPrefix("Animation studio"), true)
        XCTAssertTrue(mappa.years().contains { $0.label == "2026" })
        let weir = AuthorPage(try Demo.load(PersonAnswer.self, "api/authors/OL7234434A.json").person, id: "OL7234434A")
        XCTAssertTrue(weir.books.contains { $0.title.name == "Project Hail Mary" })
        XCTAssertTrue(weir.books.contains { $0.id == "book:OL17837968W" })
    }
}
