import SwiftUI

/// Someone else's profile (48, GET users/:username), in the same banner layout as yours: Friends ⌄ · Message ·
/// Compare, their numbers per media, how many titles you share, their last updates from the lists they let you see.
struct UserProfileView: View {
    let username: String

    var body: some View {
        PageLoader(id: username, load: { try await $0.userProfile(username) }) { page in
            UserProfileContent(page: page)
        }
        .pageBackground()
    }
}

private struct UserProfileContent: View {
    let page: UserProfile

    @Environment(AppModel.self) private var model
    @State private var media: MediaKind
    @State private var relation: Relation
    @State private var scrolled = false

    init(page: UserProfile) {
        self.page = page
        _media = State(initialValue: page.firstMedia ?? .anime)
        _relation = State(initialValue: page.person.relation)
    }

    private var name: String { page.person.username }

    var body: some View {
        let bio = page.bio
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ProfileBanner(banner: bio.banner, avatar: page.person.avatar, name: name, fade: bio.fade) {
                    let line = page.joinedLine()
                    if !line.isEmpty {
                        Text(line).font(.system(size: 14)).foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                }
                if !bio.text.isEmpty {
                    Text(bio.text).font(.system(size: 15)).foregroundStyle(Theme.inkSoft).lineSpacing(3)
                        .padding(.horizontal, Theme.pad).padding(.top, 6)
                }
                if relation != .me {
                    actions.padding(.horizontal, Theme.pad).padding(.top, 14)
                }
                if page.person.open {
                    SectionHeader("Statistics", chevron: false).padding(.top, 28)
                    ProfileMediaPicker(media: $media)
                    ProfileStatsBlock(stats: page.stats(media)) {
                        HStack(spacing: 4) {
                            Text(Format.grouped(page.inCommon(media, mine: model.library))).fontWeight(.semibold)
                                .foregroundStyle(Theme.ink)
                            Text("in common with you").foregroundStyle(Theme.inkMuted)
                        }
                    }
                    let updates = page.lastUpdates()
                    if !updates.isEmpty {
                        SectionHeader("Last updates", chevron: false).sectionGap(26)
                        LastUpdatesShelf(updates: updates)
                    }
                } else {
                    ContentUnavailableView("\(name)'s profile is hidden", systemImage: "lock",
                                           description: Text("Only the people \(name) chooses can see it."))
                        .padding(.top, 40)
                }
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .onScrollGeometryChange(for: Bool.self) { g in
            g.contentOffset.y + g.contentInsets.top > 250
        } action: { _, now in
            scrolled = now
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                    .opacity(scrolled ? 1 : 0)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: Route.user(name).url) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share profile")
                if relation != .me {
                    Menu {
                        Button { model.open(.compare(name)) } label: {
                            Label("Compare lists", systemImage: "arrow.left.arrow.right")
                        }
                        Button(role: .destructive) { block() } label: {
                            Label("Block \(name)", systemImage: "hand.raised")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
            }
        }
    }

    /// Friends ⌄ · Message · Compare (Add friend, Requested ⌄ or Accept when you aren't friends yet)
    private var actions: some View {
        HStack(spacing: 8) {
            switch relation {
            case .friend:
                Menu {
                    Button(role: .destructive) {
                        change(.none) { _ = try await $0.unfriend(name) }
                    } label: {
                        Label("Unfriend", systemImage: "person.badge.minus")
                    }
                } label: {
                    UserActionLabel(title: "Friends", symbol: "person", chevron: false)
                }
                .accessibilityLabel("Friends")
            case .outgoing:
                Menu {
                    Button(role: .destructive) {
                        change(.none) { _ = try await $0.cancelFriendRequest(name) }
                    } label: {
                        Label("Cancel request", systemImage: "xmark")
                    }
                } label: {
                    UserActionLabel(title: "Requested", symbol: "clock", chevron: true)
                }
                .accessibilityLabel("Requested")
            case .incoming:
                Button {
                    change(.friend) { _ = try await $0.answerFriend(name, accept: true) }
                } label: {
                    UserActionLabel(title: "Accept", symbol: "person.badge.plus", chevron: false)
                }
                .buttonStyle(.plain)
            case .none, .me:
                Button {
                    change(.outgoing) { _ = try await $0.requestFriend(name) }
                } label: {
                    UserActionLabel(title: "Add friend", symbol: "person.badge.plus", chevron: false)
                }
                .buttonStyle(.plain)
            }
            Button {
                model.open(.conversation(name))
            } label: {
                Label("Message", systemImage: "message")
            }
            .buttonStyle(.capsule(.tint, full: true))
            Button {
                model.open(.compare(name))
            } label: {
                Label("Compare", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(.capsule(.tone, full: true))
        }
    }

    /// shows the new relation at once and puts the old one back if the call fails
    private func change(_ to: Relation, _ call: @escaping (APIClient) async throws -> Void) {
        let was = relation
        relation = to
        Task {
            let r = await model.fetch { api -> Bool in try await call(api); return true }
            if r.value == nil { relation = was }
        }
    }

    private func block() {
        Task {
            let r = await model.fetch { try await $0.block(name) }
            if r.value != nil {
                relation = .none
                model.notice = "You blocked \(name)."
            }
        }
    }
}

/// the Friends menu's label, drawn like the kit's tone capsule (a Menu label doesn't take the button style)
private struct UserActionLabel: View {
    let title: String
    let symbol: String
    var chevron = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title).lineLimit(1).minimumScaleFactor(0.85)
            if chevron { Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).opacity(0.6) }
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(Theme.fill, in: Capsule())
        .contentShape(Capsule())
    }
}
