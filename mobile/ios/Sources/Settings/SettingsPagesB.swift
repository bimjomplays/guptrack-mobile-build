import SwiftUI
import UserNotifications

// MARK: 60 preferences

/// Settings › Preferences (60, 60b): titles, content, scores and dates. Score format is a pull-down that shows an
/// example score under each choice.
struct PreferencesSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsLoaded { s in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    titles(s)
                    scores(s)
                    dates
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .settingsPage("Preferences")
    }

    private func titles(_ s: AccountSettings) -> some View {
        SettingsGroup(label: "Titles") {
            SettingsPickerRow(label: "Title language",
                              choices: AccountSettings.TitleLanguage.allCases.map { ($0, $0.label) },
                              selection: model.settingsBinding(\.preferences.titleLanguage, fallback: .english, delay: 0))
            SettingsToggleRow(label: "Adult content", sub: "Show 18+ titles in search and browse",
                              isOn: model.settingsBinding(\.preferences.adult, fallback: false))
            SettingsToggleRow(label: "Hide spoilers", sub: "Blur episode titles and descriptions you haven't reached",
                              separator: false, isOn: model.settingsBinding(\.preferences.hideSpoilers, fallback: true))
        }
    }

    private func scores(_ s: AccountSettings) -> some View {
        SettingsGroup(label: "Scores and progress") {
            ScoreFormatMenu(selection: model.settingsBinding(\.preferences.scoreFormat, fallback: .point10, delay: 0))
            SettingsToggleRow(label: "Smart progress", sub: "Finishing the last episode marks the title Completed",
                              isOn: model.settingsBinding(\.preferences.smartProgress, fallback: true))
            SettingsToggleRow(label: "Fill in dates", sub: "Set start and finish dates as you go", separator: false,
                              isOn: model.settingsBinding(\.preferences.autoDates, fallback: true))
        }
    }

    private var dates: some View {
        SettingsGroup(label: "Dates") {
            SettingsPickerRow(label: "Date format",
                              choices: AccountSettings.DateStyle.allCases.map { ($0, $0.show(Clock.now)) },
                              selection: model.settingsBinding(\.preferences.dateFormat, fallback: .medium, delay: 0))
            SettingsPickerRow(label: "Week starts on",
                              choices: AccountSettings.WeekStart.allCases.map { ($0, $0.label) }, separator: false,
                              selection: model.settingsBinding(\.preferences.weekStart, fallback: .monday, delay: 0))
        }
    }
}

/// The Score format pull-down (60b): each choice with how 8.5 / 10 shows in it.
private struct ScoreFormatMenu: View {
    @Binding var selection: AccountSettings.ScoreFormat

    var body: some View {
        Menu {
            ForEach(AccountSettings.ScoreFormat.allCases) { f in
                Toggle(isOn: Binding(get: { selection == f }, set: { on in if on { selection = f } })) {
                    Text(f.label)
                    Text(f.example)
                }
            }
        } label: {
            SettingsRow("Score format", value: selection.label, menu: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Score format: \(selection.label)")
    }
}

// MARK: 61 notifications

/// Settings › Notifications (61): whether this iPhone may show them, then the website's switches.
struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsLoaded { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PushPermissionGroup()
                    releases
                    social
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .settingsPage("Notifications")
    }

    private func toggle(_ label: String, _ path: WritableKeyPath<AccountSettings, Bool>, sub: String? = nil,
                        last: Bool = false) -> some View {
        SettingsToggleRow(label: label, sub: sub, separator: !last, isOn: model.settingsBinding(path, fallback: false))
    }

    private var releases: some View {
        SettingsGroup(label: "Releases") {
            toggle("New episodes and chapters", \.notifications.newEpisodes, sub: "For titles you're watching or reading")
            toggle("New seasons", \.notifications.newSeasons)
            toggle("Planned titles come out", \.notifications.plannedReleases, last: true)
        }
    }

    private var social: some View {
        SettingsGroup(label: "People") {
            toggle("Friend requests", \.notifications.friendRequests)
            toggle("Comments on your profile", \.notifications.profileComments)
            toggle("Likes and replies", \.notifications.likesAndReplies)
            toggle("Messages", \.notifications.messages, last: true)
        }
    }
}

/// whether iOS lets GupTrack show notifications on this iPhone, and the way to change that
private struct PushPermissionGroup: View {
    @State private var status: UNAuthorizationStatus?
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsGroup(label: "On this iPhone", footer: footer) {
            SettingsRow("Notifications", symbol: "bell.badge", chevron: false, separator: status == .notDetermined) {
                SettingsLiveLabel(text: label, live: allowed)
            }
            if status == .notDetermined {
                Button { Task { await ask() } } label: {
                    SettingsRow("Allow notifications", chevron: false, separator: false, tint: true)
                }
                .buttonStyle(.plain)
            }
        }
        .task { await check() }
    }

    private var allowed: Bool { status == .authorized || status == .provisional || status == .ephemeral }

    private var label: String {
        switch status {
        case .none: return "Checking"
        case .notDetermined: return "Not asked yet"
        case .denied: return "Off"
        default: return "Allowed"
        }
    }

    private var footer: String {
        status == .denied
            ? "Notifications are off for GupTrack in the iPhone's Settings app. Turn them on there to get the ones below."
            : "The switches below follow your account, so the website and this iPhone match."
    }

    private func check() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func ask() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        await check()
    }
}

// MARK: server

/// Settings › Server: the GupTrack server this iPhone talks to (from GET hello), who's signed in, this device.
struct ServerSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PageLoader(load: { try await $0.hello() }) { hello in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    server(hello)
                    you
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .settingsPage("Server")
    }

    private func server(_ hello: ServerHello) -> some View {
        let state = SettingsConnection.state(model.sync)
        return SettingsGroup(label: "Server", footer: "Your library lives on this server. The iPhone keeps a copy to use offline.") {
            SettingsRow("Status", chevron: false) { SettingsLiveLabel(text: state.0, live: state.1) }
            SettingsRow("Address", value: model.account?.baseURL.host ?? "", chevron: false)
            SettingsRow("Name", value: hello.name, chevron: false)
            SettingsRow("Version", value: "\(hello.version) · API \(hello.api)", chevron: false)
            SettingsRow("New accounts", value: AccountList.joiningLabel(hello.joining), chevron: false, separator: false)
        }
    }

    @ViewBuilder private var you: some View {
        if let a = model.account {
            SettingsGroup(label: "This iPhone") {
                SettingsRow("Signed in as", value: "@" + a.user.username, chevron: false)
                SettingsRow("Since", value: Format.longDay(a.signedInAt), chevron: false)
                SettingsRow("Device", value: a.deviceId, chevron: false, separator: false)
            }
        }
    }
}

// MARK: offline library

/// Settings › Offline library: the copy of the library on this iPhone, what's waiting to send, Sync now.
struct OfflineLibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsGroup(footer: "Changes you make without a connection wait here and are sent the next time your server is reachable.") {
                    SettingsRow("Status", chevron: false) { SettingsLiveLabel(text: state.0, live: state.1) }
                    SettingsRow("On this iPhone", value: SettingsText.titles(model.library.count), chevron: false)
                    SettingsRow("Waiting to send", value: SettingsText.pending(model.pendingCount), chevron: false)
                    SettingsRow("Last synced", value: lastSynced, chevron: false, separator: false)
                }
                Button { Task { await model.syncLibrary() } } label: {
                    if model.sync == .syncing {
                        ProgressView().tint(.white)
                    } else {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.capsule(.tint, .large, full: true))
                .disabled(model.sync == .syncing)
                .padding(.horizontal, Theme.pad)
            }
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .settingsPage("Offline library")
    }

    private var state: (String, Bool) {
        if case .offline(let why) = model.sync { return (why.isEmpty ? "Offline" : why, false) }
        if case .failed(let why) = model.sync { return (why.isEmpty ? "Error" : why, false) }
        return SettingsConnection.state(model.sync)
    }

    private var lastSynced: String {
        guard let d = model.lastSynced else { return "Not yet" }
        return SettingsText.dayName(d) + ", " + Format.time(d)
    }
}

// MARK: widgets

/// Settings › Widgets: the app's widgets and how to put one on the Home Screen.
struct WidgetSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsGroup(label: "GupTrack widgets") {
                    ForEach(WidgetGuide.widgets) { w in
                        SettingsRow(w.name, symbol: w.symbol, sub: w.about, value: w.sizes, chevron: false,
                                    separator: w.id != WidgetGuide.widgets.last?.id)
                    }
                }
                SettingsGroup(label: "Add one to your Home Screen") {
                    ForEach(Array(WidgetGuide.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text("\(i + 1)").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                                .frame(width: 26).numbers()
                            Text(step).font(.system(size: 17)).foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, Theme.pad).padding(.trailing, Theme.pad).padding(.vertical, 13)
                        .overlay(alignment: .bottom) {
                            if i < WidgetGuide.steps.count - 1 { Hairline().padding(.leading, Theme.pad + 40) }
                        }
                    }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .settingsPage("Widgets")
    }
}
