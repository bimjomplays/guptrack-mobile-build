import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// The people pages (28 character, 29 person, 30 studio, 31 author): their fixtures decode and their logic.
final class PeopleTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func files(_ folder: String) -> [String] {
        let dir = Demo.root.appendingPathComponent("api/" + folder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted().map { "api/\(folder)/\($0)" }
    }

    private func library() throws -> [LibraryEntry] { try Demo.load([LibraryEntry].self, "api/library.json") }

    // MARK: every fixture decodes, and its id is the one its file is named for

    func testEveryPeopleFixtureDecodes() throws {
        let sets: [(String, (String) throws -> String)] = [
            ("characters", { try Demo.load(CharacterPage.self, $0).id }),
            ("people", { try Demo.load(PersonPage.self, $0).id }),
            ("studios", { try Demo.load(StudioPage.self, $0).id }),
            ("authors", { try Demo.load(AuthorPage.self, $0).id }),
        ]
        for (folder, load) in sets {
            let list = files(folder)
            XCTAssertGreaterThan(list.count, 1, folder)
            for f in list {
                let id = try load(f)
                XCTAssertEqual(Demo.file(folder + "/" + id), f, "\(f) holds \(id)")
            }
        }
    }

    func testIdsTheTitlePagesLinkWith() {
        for path in ["characters/character:40", "people/person:95075", "people/person:tmdb-1190668",
                     "studios/studio:569", "studios/studio:tmdb-49", "studios/studio:tmdb-41077",
                     "authors/author:OL7234434A"] {
            XCTAssertNotNil(Demo.data(Demo.file(path)), path)
        }
        XCTAssertEqual(Route(path: "character/character:40"), .character("character:40"))
        XCTAssertEqual(Route(path: "person/person:tmdb-1190668"), .person("person:tmdb-1190668"))
    }

    // MARK: 28 character

    func testLuffy() throws {
        let c = try Demo.load(CharacterPage.self, "api/characters/character_40.json")
        XCTAssertEqual(c.name, "Monkey D. Luffy")
        XCTAssertEqual(c.headline, "Main character · ONE PIECE")
        XCTAssertEqual(c.facts.map(\.value), ["172 cm", "May 5", "17–19", "Male"])
        XCTAssertEqual(c.facts.map(\.label), ["Height", "Birthday", "Age", "Gender"])
        XCTAssertTrue(c.prose.text.hasPrefix("Luffy is the captain of the Straw Hat Pirates"))
        XCTAssertFalse(c.prose.text.contains("Nika"), "spoilers stay hidden")
        XCTAssertFalse(c.prose.text.contains("]("), "links keep only their words")
        XCTAssertTrue(c.prose.text.contains("such as Buggy the Clown and Alvida"))
        XCTAssertEqual(c.voices.first?.id, "person:95075")
        XCTAssertEqual(c.voices.first?.line, "Japanese · 田中真弓")
        XCTAssertEqual(c.total, 12)
        XCTAssertEqual(c.appearances.prefix(2).map(\.line), ["TV · 1999 · Main", "Manga · 1997 · Main"])
        let film = c.appearances.first { $0.title.id == "anime:141902" }
        XCTAssertEqual(film?.title.media, .anime, "anime films stay under Anime")
        XCTAssertEqual(film.map { PeopleCaption.format($0.title) }, "Film")
    }

    func testProseSpoilersAndFacts() {
        let p = PeopleProse("__Height:__ 160 cm\n__Bounty:__ ~!a lot!~\n\nShe is ~!secretly a queen and!~ kind.\n\n[Profile](https://x.example)")
        XCTAssertEqual(p.fact("height"), "160 cm")
        XCTAssertNil(p.fact("Bounty"), "a hidden fact isn't shown")
        XCTAssertEqual(p.text, "She is kind.")
        XCTAssertEqual(p.full, "She is secretly a queen and kind.")
        XCTAssertTrue(p.hasSpoilers)
        XCTAssertEqual(PeopleProse(nil).text, "")
    }

    func testDates() {
        XCTAssertEqual(PeopleDate(year: nil, month: 5, day: 5).text, "May 5")
        XCTAssertEqual(PeopleDate(year: 1995, month: 12, day: 27).text, "Dec 27, 1995")
        XCTAssertEqual(PeopleDate(year: 1955, month: 1, day: nil).text, "Jan 1955")
    }

    // MARK: 29 person

    func testChalamet() throws {
        let p = try Demo.load(PersonPage.self, "api/people/person_tmdb-1190668.json")
        XCTAssertEqual(p.headline, "Actor · 66 credits")
        XCTAssertEqual(p.bornLine, "Born Dec 27, 1995 · New York City")
        XCTAssertEqual(p.creditsTitle, "Filmography")
        XCTAssertEqual(p.groups.map(\.label), ["Movies 52", "TV 14"])
        let films = p.credits(.movie)
        XCTAssertEqual(films.first?.title.name, "Marty Supreme")
        XCTAssertEqual(films.first?.line, "as Marty Mauser")
        XCTAssertEqual(films.compactMap(\.year), films.compactMap(\.year).sorted(by: >))
        XCTAssertEqual(p.knownFor.prefix(2).map(\.name), ["Dune", "Dune: Part Two"])
        XCTAssertTrue(p.prose.text.hasPrefix("Timothée Hal Chalamet"))
    }

    func testMayumiTanakaListsHerRoles() throws {
        let p = try Demo.load(PersonPage.self, "api/people/person_95075.json")
        XCTAssertTrue(p.isVoice)
        XCTAssertEqual(p.creditsTitle, "Roles")
        XCTAssertEqual(p.groups.map(\.media), [.anime])
        XCTAssertTrue(p.headline.hasPrefix("Voice actor · "))
        let luffy = p.credits.first { $0.character?.name == "Luffy Monkey" }
        XCTAssertEqual(luffy?.character?.id, "character:40")
        XCTAssertEqual(luffy?.line, "ONE PIECE · Main")
        XCTAssertFalse(p.prose.text.contains("Profile"), "a paragraph that was only a link goes")
        XCTAssertEqual(p.prose.fact("Agency"), "Aoni Production")
    }

    // MARK: 30 studio

    func testMappa() throws {
        let s = try Demo.load(StudioPage.self, "api/studios/studio_569.json")
        XCTAssertEqual(s.headline, "Animation studio · Tokyo, Japan")
        XCTAssertEqual(s.filters.map(\.label), ["All", "TV", "Films", "ONA"])
        let years = s.years()
        XCTAssertEqual(years.first?.label, "2026")
        XCTAssertEqual(years.last?.label, "TBA")
        XCTAssertEqual(years.first?.titles.first?.id, "anime:172463")
        XCTAssertTrue(s.years(.film).flatMap(\.titles).allSatisfy { PeopleCaption.format($0) == "Film" })
        XCTAssertEqual(s.years(.tv).flatMap(\.titles).count, s.titles.filter { $0.format == "TV" }.count)
        let n = s.inLibrary(try library())
        XCTAssertEqual(s.countLine(inLibrary: n), n > 0 ? "24 titles · \(n) in your library" : "24 titles")
    }

    func testNetworksUseTheSamePage() throws {
        let hbo = try Demo.load(StudioPage.self, "api/studios/studio_tmdb-49.json")
        XCTAssertEqual(hbo.name, "HBO")
        XCTAssertTrue(hbo.titles.allSatisfy { StudioPage.Filter.of($0) == .tv })
        XCTAssertEqual(hbo.filters, [], "one kind of title: no filter")
        XCTAssertEqual(hbo.countLine(inLibrary: 1), "2 titles · 1 in your library")
    }

    // MARK: 31 author

    func testAndyWeir() throws {
        let a = try Demo.load(AuthorPage.self, "api/authors/author_OL7234434A.json")
        XCTAssertEqual(a.headline, "Author · Science fiction")
        XCTAssertEqual(a.bornLine, "Born Jun 16, 1972 · Davis, California")
        XCTAssertEqual(a.books.count, 3)
        XCTAssertEqual(a.pages, 1_225)
        XCTAssertEqual(a.averageRating, "4.2")
        XCTAssertEqual(a.sorted().map(\.title.name), ["Project Hail Mary", "Artemis", "The Martian"])
        XCTAssertEqual(a.sorted(newestFirst: false).first?.title.name, "The Martian")
        XCTAssertEqual(a.sorted().first?.line, "2021 · 496 pages")
        let lib = try library()
        XCTAssertEqual(a.inLibrary(lib), a.books.filter { b in lib.contains { $0.id == b.id } }.count)
        let e = LibraryEntry(title: a.sorted()[0].title, status: .current, progress: 212, updatedAt: Clock.demoNow)
        XCTAssertEqual(AuthorPage.pageLine(e), "p. 212 of 496")
    }
}
