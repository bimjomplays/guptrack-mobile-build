import SwiftUI

/// Someone else's profile (48), in the same banner layout as yours: Friends ⌄ · Message · Compare, their numbers
/// per media (from the server), how many titles you share, their last updates.
struct UserProfileView: View {
    let username: String

    var body: some View {
        PageLoader(id: username, load: { try await $0.userPage(username) }) { page in
            UserProfileContent(page: page)
        }
        .pageBackground()
    }
}

private struct UserProfileContent: View {
    let page: UserPage

    @Environment(AppModel.self) private var model
    @State private var media: MediaKind = .anime
    @State private var friendship: String?
    @State private var scrolled = false

    private var name: String { page.user.username }
    private var friends: Bool { (friendship ?? page.friendship) == "friends" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ProfileBanner(banner: page.banner, avatar: page.user.avatar, name: name, fade: page.fade) {
                    Text(page.joinedLine).font(.system(size: 14)).foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                if !page.bio.isEmpty {
                    Text(page.bio).font(.system(size: 15)).foregroundStyle(Theme.inkSoft).lineSpacing(3)
                        .padding(.horizontal, Theme.pad).padding(.top, 6)
                }
                actions.padding(.horizontal, Theme.pad).padding(.top, 14)
                SectionHeader("Statistics", chevron: false).padding(.top, 28)
                ProfileMediaPicker(media: $media)
                ProfileStatsBlock(summary: page.summary(media)) {
                    HStack(spacing: 4) {
                        Text(Format.grouped(page.inCommon(media))).fontWeight(.semibold).foregroundStyle(Theme.ink)
                        Text("in common with you").foregroundStyle(Theme.inkMuted)
                    }
                }
                if !page.lastUpdates.isEmpty {
                    SectionHeader("Last updates", chevron: false).sectionGap(26)
                    LastUpdatesShelf(updates: page.lastUpdates)
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
                Menu {
                    Button { model.open(.compare(name)) } label: {
                        Label("Compare lists", systemImage: "arrow.left.arrow.right")
                    }
                    Button(role: .destructive) { post("users/\(name)/block", done: "You blocked \(name).") } label: {
                        Label("Block \(name)", systemImage: "hand.raised")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
    }

    /// Friends ⌄ · Message · Compare
    private var actions: some View {
        HStack(spacing: 8) {
            if friends {
                Menu {
                    Button(role: .destructive) {
                        friendship = "none"
                        post("friends/\(name)/remove", done: nil)
                    } label: {
                        Label("Unfriend", systemImage: "person.badge.minus")
                    }
                } label: {
                    UserActionLabel(title: "Friends", symbol: "person.crop.circle.badge.checkmark", chevron: true)
                }
                .accessibilityLabel("Friends")
            } else {
                Button {
                    friendship = "requested"
                    post("friends/\(name)/request", done: nil)
                } label: {
                    UserActionLabel(title: (friendship ?? page.friendship) == "requested" ? "Requested" : "Add friend",
                                    symbol: "person.badge.plus", chevron: false)
                }
                .buttonStyle(.plain)
                .disabled((friendship ?? page.friendship) == "requested")
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

    private func post(_ path: String, done: String?) {
        Task {
            let r = await model.fetch { api -> OKReply in try await api.send("POST", path) }
            if r.value != nil, let done { model.notice = done }
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
            Text(title).lineLimit(1)
            if chevron { Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).opacity(0.6) }
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(Theme.fill, in: Capsule())
        .contentShape(Capsule())
    }
}
