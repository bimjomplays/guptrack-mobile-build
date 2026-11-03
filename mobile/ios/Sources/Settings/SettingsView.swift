import SwiftUI

/// Settings (55, 55b): pushed from Profile's gear. The website's sections in its order as plain hairline rows, then
/// This iPhone (server, offline library, widgets) and Sign out.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false

    var body: some View {
        SettingsLoaded { s in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(s)
                    yours(s)
                    app(s)
                    data(s)
                    SettingsPhoneGroup()
                    signOut
                    Text(appVersion)
                        .font(.system(size: 13)).foregroundStyle(Theme.inkFaint).numbers()
                        .frame(maxWidth: .infinity)
                        .padding(.top, -4)
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .pageBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Sign out of GupTrack on this iPhone?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await model.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your library stays on your PC. Changes not sent yet are lost.")
        }
    }

    private func link<V: View>(_ page: SettingsPage, @ViewBuilder _ row: () -> V) -> some View {
        NavigationLink(value: Route.settingsPage(page)) { row() }.buttonStyle(.plain)
    }

    private func header(_ s: AccountSettings) -> some View {
        link(.profile) {
            HStack(spacing: 14) {
                Avatar(url: s.profile.avatar, size: 60)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.profile.displayName).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                    Text(s.accountLine).font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.inkFaint)
            }
            .padding(.horizontal, Theme.pad)
            .padding(.bottom, 22)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
    }

    private func yours(_ s: AccountSettings) -> some View {
        SettingsGroup {
            link(.profile) { SettingsRow("Profile", symbol: "person", sub: "Name, picture, banner, bio") }
            // no Account page in the app yet: username, password and passkeys live on the profile page for now
            link(.profile) { SettingsRow("Account", symbol: "key", sub: "Username, password, passkeys") }
            link(.privacy) { SettingsRow("Privacy", symbol: "lock", value: s.privacy.profile.label, separator: false) }
        }
    }

    private func app(_ s: AccountSettings) -> some View {
        SettingsGroup {
            link(.appearance) { SettingsRow("Appearance", symbol: "paintpalette", value: s.theme) }
            link(.preferences) {
                SettingsRow("Preferences", symbol: "slider.horizontal.3", value: s.preferences.titleLanguage.label)
            }
            link(.notifications) { SettingsRow("Notifications", symbol: "bell", separator: false) }
        }
    }

    private func data(_ s: AccountSettings) -> some View {
        SettingsGroup {
            // no Data sources page in the app yet: Import & export is the closest
            link(.importExport) {
                SettingsRow("Data sources", symbol: "cylinder.split.1x2", value: "\(s.summary.sourcesOn) on")
            }
            link(.importExport) { SettingsRow("Import & export", symbol: "arrow.down.to.line") }
            link(.connectedApps) { SettingsRow("Connected apps", symbol: "powerplug", value: s.connectedValue) }
            link(.backups) {
                SettingsRow("Backups", symbol: "archivebox", value: s.backupValue, separator: s.account.isOwner)
            }
            if s.account.isOwner {
                link(.accounts) {
                    SettingsRow("Accounts", symbol: "person.2", value: "\(s.summary.accounts)", separator: false)
                }
            }
        }
    }

    private var signOut: some View {
        SettingsGroup(footer: "Signs this iPhone out of your GupTrack server. Your library stays on the PC.") {
            Button { confirmSignOut = true } label: {
                SettingsRow("Sign out", symbol: "rectangle.portrait.and.arrow.right", chevron: false, separator: false,
                            danger: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "GupTrack for iPhone \(v) (\(b))"
    }
}

/// This iPhone: the server connection, the offline library, widgets.
private struct SettingsPhoneGroup: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsGroup(label: "This iPhone",
                      footer: "Changes you make offline are sent to your PC the next time it’s reachable.") {
            NavigationLink(value: Route.settingsPage(.server)) {
                SettingsRow("Server", symbol: "server.rack", sub: model.account?.baseURL.host) {
                    SettingsLiveLabel(text: connection.0, live: connection.1)
                }
            }
            .buttonStyle(.plain)
            NavigationLink(value: Route.settingsPage(.offline)) {
                SettingsRow("Offline library", symbol: "icloud.and.arrow.down", sub: SettingsText.synced(model.lastSynced),
                            value: SettingsText.titles(model.library.count))
            }
            .buttonStyle(.plain)
            NavigationLink(value: Route.settingsPage(.widgets)) {
                SettingsRow("Widgets", symbol: "square.grid.2x2", separator: false)
            }
            .buttonStyle(.plain)
        }
    }

    private var connection: (String, Bool) { SettingsConnection.state(model.sync) }
}

/// how the server connection reads from the sync state
enum SettingsConnection {
    static func state(_ sync: SyncState) -> (String, Bool) {
        switch sync {
        case .idle: return ("Connected", true)
        case .syncing: return ("Syncing", true)
        case .offline: return ("Offline", false)
        case .failed: return ("Error", false)
        }
    }
}
