import SwiftUI

/// A page under Settings.
struct SettingsPageView: View {
    let page: SettingsPage

    var body: some View {
        switch page {
        case .profile: ProfileSettingsView()
        case .account: AccountPageView()
        case .privacy: PrivacySettingsView()
        case .appearance: AppearanceSettingsView()
        case .preferences: PreferencesSettingsView()
        case .notifications: NotificationSettingsView()
        case .importExport: ImportExportView()
        case .connectedApps: ConnectedAppsView()
        case .backups: BackupsView()
        case .accounts: AccountsSettingsView()
        case .server: ServerSettingsView()
        case .offline: OfflineLibraryView()
        case .widgets: WidgetSettingsView()
        }
    }
}
