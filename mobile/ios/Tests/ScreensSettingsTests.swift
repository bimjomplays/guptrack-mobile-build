import XCTest
@testable import GupTrack

/// Settings (55-64b): the root, Profile with the bio editor, Privacy, Appearance, Preferences, Notifications,
/// Account, Import & export, Connected apps, Backups, Accounts.
final class ScreensSettingsTests: ScreenTestCase {
    /// a settings page on top of Profile › Settings, with the shared settings loaded fresh (edits in one test stay
    /// out of the next)
    private func open(_ page: String? = nil, _ more: [String] = []) -> App {
        AccountSettingsStore.shared.settings = nil
        var flags = ["-tab", "profile", "-open", "settings"]
        if let page { flags += ["-open", "settings/" + page] }
        return launch(flags + more)
    }

    func testSettings() {
        let app = open()
        expect(app, "Mika")
        expect(app, "Owner · Joined Sep 9, 2025")
        expect(app, "Privacy")
        expect(app, "Appearance")
        expect(app, "Dark")
        expect(app, "Connected apps")
        shot("55-settings")
    }

    func testSettingsScrolled() {
        let app = open()
        expect(app, "Appearance")
        scroll(app, until: "This iPhone", top: 120)
        expect(app, "Offline library")
        expect(app, "Widgets")
        expect(app, "Sign out")
        shot("55b-settings-scrolled")
    }

    func testProfilePage() {
        let app = open("profile")
        expect(app, "Banner fade")
        expect(app, "Banner")
        expect(app, "Seasonal anime, slow manga")
        expect(app, "Fade colour")
        shot("56-settings-profile")
    }

    func testBioEditor() {
        let app = open("profile", ["-sheet", "bio-editor"])
        expect(app, "Edit bio")
        expect(app, "Presets")
        expect(app, "Editorial")
        expect(app, "Favourite anime")
        XCTAssertTrue(app.buttons["Insert list"].exists)
        shot("57-bio-editor")
    }

    func testPrivacy() {
        let app = open("privacy")
        expect(app, "Who can see your profile")
        expect(app, "Friends")
        expect(app, "Movies")
        expect(app, "Messages")
        shot("58-settings-privacy")
    }

    func testAppearance() {
        let app = open("appearance")
        expect(app, "Classic")
        expect(app, "Midnight")
        expect(app, "Pastel")
        shot("59-settings-appearance")
    }

    func testPreferences() {
        let app = open("preferences")
        expect(app, "Title language")
        expect(app, "Score format")
        expect(app, "Hide spoilers")
        shot("60-settings-preferences")
    }

    func testScoreFormatMenu() {
        let app = open("preferences")
        expect(app, "Score format").tap()
        expect(app, "10 point decimal")
        expect(app, "3 point smiley")
        shot("60b-settings-score-format")
    }

    func testNotifications() {
        let app = open("notifications")
        expect(app, "On this iPhone")
        expect(app, "New episodes")
        expect(app, "Friend requests")
        shot("61-settings-notifications")
    }

    func testImport() {
        let app = open("import")
        expect(app, "Import from")
        expect(app, "AniList")
        expect(app, "Goodreads")
        expect(app, "Every list as CSV")
        expect(app, "Full backup")
        shot("62-settings-import")
    }

    func testConnectedApps() {
        let app = open("connected-apps")
        expect(app, "Harbor on the living-room PC")
        expect(app, "This iPhone")
        expect(app, "Pair Harbor").tap()
        expect(app, "7KQ4-M2XD")
        shot("63-settings-connected-apps")
    }

    func testBackups() {
        let app = open("backups")
        expect(app, "Back up now")
        expect(app, "1.8 MB")
        expect(app, "Before a restore")
        shot("64-settings-backups")
    }

    func testAccounts() {
        let app = open("accounts")
        expect(app, "kenji")
        expect(app, "lena")
        expect(app, "5 accounts")
        expect(app, "New invite")
        shot("64b-settings-accounts")
    }

    // MARK: behaviour

    func testRowOpensPrivacy() {
        let app = open()
        expect(app, "Privacy").tap()
        XCTAssertEqual(app.model.path(.profile).last, .settingsPage(.privacy))
    }

    func testCheckmarkSavesPrivacy() {
        let app = open("privacy")
        expect(app, "Who can see your profile")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Private")).firstMatch.tap()
        XCTAssertTrue(poll(3) { AccountSettingsStore.shared.settings?.privacy.visibility == .private })
        XCTAssertTrue(poll(3) { AccountSettingsStore.shared.pendingChanges.isEmpty })
    }

    func testBioRowOpensEditor() {
        let app = open("profile")
        expect(app, "Banner fade")
        expect(app, "Bio").tap()
        XCTAssertEqual(app.model.sheet, .bioEditor)
    }

    func testSignOutAsksFirst() {
        let app = open()
        expect(app, "Appearance")
        scroll(app, until: "Sign out", top: 300)
        find(app, "Sign out").tap()
        expect(app, "Sign out of GupTrack on this iPhone?")
        XCTAssertNotNil(app.model.account)
    }

    func testAccount() {
        let app = open("account")
        expect(app, "Change password")
        expect(app, "Codes left")
        expect(app, "Browsers signed in")
        expect(app, "Sign out everywhere")
        XCTAssertFalse(find(app, "Add passkey").exists)
    }

    func testOfflineLibrary() {
        let app = open("offline")
        expect(app, "Waiting to send")
        XCTAssertTrue(app.buttons["Sync now"].exists)
    }

    func testServer() {
        let app = open("server")
        expect(app, "Signed in as")
        expect(app, "@mika")
    }
}
