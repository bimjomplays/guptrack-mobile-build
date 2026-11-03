import Foundation

/// The app's five tabs.
enum AppTab: String, CaseIterable, Hashable, Sendable {
    case home, browse, library, social, profile
}

/// Every page that can be pushed on a tab's navigation stack. A route also has a path form ("title/anime:210482"),
/// used by links (guptrack://title/anime:210482 from the widget and share extension) and the demo's `-open` flag.
enum Route: Hashable, Sendable {
    // Home
    case notifications
    case calendar
    // Browse
    case seasonChart
    case search(String)
    // Titles and the people around them
    case title(String)                 // title id
    case season(String, Int)           // TV title id, season number
    case reviews(String)               // a title's reviews
    case review(String)                // one review with its replies
    case character(String)
    case person(String)
    case studio(String)
    case author(String)
    // Library
    case list(MediaKind)
    case customList(String)
    // Profile and people
    case stats
    case user(String)                  // username
    case compare(String)               // username
    case friends
    // Social
    case activity(String)              // one activity with its comments
    case conversation(String)          // conversation id
    case messageRequest(String)
    // Settings
    case settings
    case settingsPage(SettingsPage)

    /// "title/anime:210482", "season/tv:95396/2", "list/anime", "settings/privacy"
    var path: String {
        switch self {
        case .notifications: return "notifications"
        case .calendar: return "calendar"
        case .seasonChart: return "season-chart"
        case .search(let q): return "search/" + (q.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? q)
        case .title(let id): return "title/" + id
        case .season(let id, let n): return "season/\(id)/\(n)"
        case .reviews(let id): return "reviews/" + id
        case .review(let id): return "review/" + id
        case .character(let id): return "character/" + id
        case .person(let id): return "person/" + id
        case .studio(let id): return "studio/" + id
        case .author(let id): return "author/" + id
        case .list(let m): return "list/" + m.rawValue
        case .customList(let id): return "custom-list/" + id
        case .stats: return "stats"
        case .user(let u): return "user/" + u
        case .compare(let u): return "compare/" + u
        case .friends: return "friends"
        case .activity(let id): return "activity/" + id
        case .conversation(let id): return "conversation/" + id
        case .messageRequest(let id): return "message-request/" + id
        case .settings: return "settings"
        case .settingsPage(let p): return "settings/" + p.rawValue
        }
    }

    init?(path raw: String) {
        let parts = raw.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let head = parts.first else { return nil }
        let arg = parts.count > 1 ? parts[1] : nil
        func one(_ make: (String) -> Route) -> Route? {
            guard parts.count == 2, let arg, !arg.isEmpty else { return nil }
            return make(arg)
        }
        let r: Route?
        switch head {
        case "notifications": r = parts.count == 1 ? .notifications : nil
        case "calendar": r = parts.count == 1 ? .calendar : nil
        case "season-chart": r = parts.count == 1 ? .seasonChart : nil
        case "search": r = one { .search($0.removingPercentEncoding ?? $0) }
        case "title": r = one { .title($0) }
        case "season":
            if parts.count == 3, let n = Int(parts[2]) { r = .season(parts[1], n) } else { r = nil }
        case "reviews": r = one { .reviews($0) }
        case "review": r = one { .review($0) }
        case "character": r = one { .character($0) }
        case "person": r = one { .person($0) }
        case "studio": r = one { .studio($0) }
        case "author": r = one { .author($0) }
        case "list": r = arg.flatMap(MediaKind.init(rawValue:)).flatMap { parts.count == 2 ? .list($0) : nil }
        case "custom-list": r = one { .customList($0) }
        case "stats": r = parts.count == 1 ? .stats : nil
        case "user": r = one { .user($0) }
        case "compare": r = one { .compare($0) }
        case "friends": r = parts.count == 1 ? .friends : nil
        case "activity": r = one { .activity($0) }
        case "conversation": r = one { .conversation($0) }
        case "message-request": r = one { .messageRequest($0) }
        case "settings":
            if parts.count == 1 { r = .settings }
            else { r = arg.flatMap(SettingsPage.init(rawValue:)).flatMap { parts.count == 2 ? .settingsPage($0) : nil } }
        default: r = nil
        }
        guard let r else { return nil }
        self = r
    }

    /// the tab a link to this page opens in
    var homeTab: AppTab {
        switch self {
        case .notifications, .calendar: return .home
        case .seasonChart, .search, .title, .season, .reviews, .review, .character, .person, .studio, .author:
            return .browse
        case .list, .customList: return .library
        case .activity, .conversation, .messageRequest, .friends, .user, .compare: return .social
        case .stats, .settings, .settingsPage: return .profile
        }
    }

    /// guptrack://title/anime:210482 -> .title("anime:210482")
    init?(url: URL) {
        guard url.scheme?.lowercased() == "guptrack", let host = url.host, !host.isEmpty else { return nil }
        self.init(path: host + url.path)
    }

    var url: URL { URL(string: "guptrack://" + path)! }
}

/// The pages under Settings, in the website's order.
enum SettingsPage: String, CaseIterable, Hashable, Sendable {
    case profile, account, privacy, appearance, preferences, notifications, importExport = "import",
         connectedApps = "connected-apps", backups, accounts, server, offline, widgets

    var label: String {
        switch self {
        case .profile: return "Profile"
        case .account: return "Account"
        case .privacy: return "Privacy"
        case .appearance: return "Appearance"
        case .preferences: return "Preferences"
        case .notifications: return "Notifications"
        case .importExport: return "Import & export"
        case .connectedApps: return "Connected apps"
        case .backups: return "Backups"
        case .accounts: return "Accounts"
        case .server: return "Server"
        case .offline: return "Offline library"
        case .widgets: return "Widgets"
        }
    }
}

/// Sheets the app shows over a page.
enum SheetRoute: Hashable, Identifiable, Sendable {
    case editor(String, expanded: Bool)     // the list editor for a title
    case addToList(String)                  // tick custom lists for a title
    case writeReview(String)
    case sendTo(String)                     // send a title to friends
    case browseFilters(MediaKind)
    case newList
    case editList(String)
    case addFriend
    case bioEditor
    case newMessage

    var id: String {
        switch self {
        case .editor(let t, let x): return "editor/\(t)/\(x)"
        case .addToList(let t): return "add-to-list/" + t
        case .writeReview(let t): return "write-review/" + t
        case .sendTo(let t): return "send-to/" + t
        case .browseFilters(let m): return "filters/" + m.rawValue
        case .newList: return "new-list"
        case .editList(let id): return "edit-list/" + id
        case .addFriend: return "add-friend"
        case .bioEditor: return "bio-editor"
        case .newMessage: return "new-message"
        }
    }

    init?(id: String) {
        let p = id.split(separator: "/").map(String.init)
        switch p.first {
        case "editor" where p.count == 3: self = .editor(p[1], expanded: p[2] == "true")
        case "editor" where p.count == 2: self = .editor(p[1], expanded: false)
        case "add-to-list" where p.count == 2: self = .addToList(p[1])
        case "write-review" where p.count == 2: self = .writeReview(p[1])
        case "send-to" where p.count == 2: self = .sendTo(p[1])
        case "filters" where p.count == 2:
            guard let m = MediaKind(rawValue: p[1]) else { return nil }
            self = .browseFilters(m)
        case "new-list" where p.count == 1: self = .newList
        case "edit-list" where p.count == 2: self = .editList(p[1])
        case "add-friend" where p.count == 1: self = .addFriend
        case "bio-editor" where p.count == 1: self = .bioEditor
        case "new-message" where p.count == 1: self = .newMessage
        default: return nil
        }
    }
}
