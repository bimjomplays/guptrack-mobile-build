import XCTest
@testable import GupTrack

/// People (28 character, 29 person, 30 studio, 31 author).
final class ScreensPeopleTests: ScreenTestCase {
    func testCharacter() {
        let app = launch(["-open", "character/40"])
        expect(app, "Monkey D. Luffy")
        expect(app, "About")
        expect(app, "Voiced by")
        expect(app, "Mayumi Tanaka")
        expect(app, "Appears in")
        shot("28-character")
    }

    func testPerson() {
        let app = launch(["-open", "person/tmdb:1190668"])
        expect(app, "Timothée Chalamet")
        expect(app, "Known for")
        expect(app, "Acting")
        shot("29-person")
    }

    func testStudio() {
        let app = launch(["-open", "studio/studio:569"])
        expect(app, "MAPPA")
        expect(app, "Animation studio")
        expect(app, "2026")
        shot("30-studio")
    }

    func testAuthor() {
        let app = launch(["-open", "author/OL7234434A"])
        expect(app, "Andy Weir")
        expect(app, "Books")
        expect(app, "Project Hail Mary")
        shot("31-author")
    }

    func testVoiceRowOpensTheVoiceActor() {
        let app = launch(["-open", "character/40"])
        expect(app, "Mayumi Tanaka").tap()
        XCTAssertEqual(app.model.path(.browse).last, .person("anilist:95075"))
    }

    func testAppearanceOpensItsTitle() {
        let app = launch(["-open", "character/40"])
        expect(app, "Appears in")
        scroll(app, until: "TV · 1999", top: 420)
        expect(app, "TV · 1999").tap()
        XCTAssertEqual(app.model.path(.browse).last, .title("anime:21"))
    }

    func testVoiceActorListsRoles() {
        let app = launch(["-open", "person/anilist:95075"])
        expect(app, "Mayumi Tanaka")
        expect(app, "Voice roles")
        expect(app, "Monkey D. Luffy")
    }

    func testPlanToReadAddsTheBook() {
        let app = launch(["-open", "author/OL7234434A"])
        expect(app, "Andy Weir")
        XCTAssertNil(app.model.entry("book:OL17837968W"))
        scroll(app, until: "Artemis", top: 300)
        app.buttons.matching(NSPredicate(format: "label == %@", "Plan to Read")).firstMatch.tap()
        XCTAssertEqual(app.model.entry("book:OL17837968W")?.status, .planned)
    }
}
