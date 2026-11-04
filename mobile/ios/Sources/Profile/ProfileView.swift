import SwiftUI

/// Your profile, the Profile tab (41, 42): your banner, picture and bio; your numbers per media from the profile
/// answer (GET profile); last updates from the offline library; then your lists, favourites, reviews and the comments
/// people left you. Editing happens in
/// Settings › Profile (the gear), so there's no Edit button here; friends is a small link by your name.
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var page: MyProfile?
    @State private var failed: String?
    @State private var scrolled = false
    @AppStorage(MediaKind.profileKey) private var mediaRaw = MediaKind.anime.rawValue

    private var media: Binding<MediaKind> {
        Binding(get: { MediaKind(rawValue: mediaRaw) ?? .anime }, set: { mediaRaw = $0.rawValue })
    }

    private var name: String {
        if let n = page?.profile.name, !n.isEmpty { return n }
        return model.account?.user.name ?? "Profile"
    }
    private var username: String { model.account?.user.username ?? "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let page {
                    content(page)
                } else if let failed {
                    ContentUnavailableView {
                        Label("Couldn't load your profile", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(failed)
                    } actions: {
                        Button("Try again") { Task { await load() } }.buttonStyle(.capsule(.tone, .small))
                    }
                    .padding(.top, 120)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 200)
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
        .pageBackground()
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                    .opacity(scrolled ? 1 : 0)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: Route.user(username).url) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share profile")
                Button {
                    model.open(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .task { if page == nil { await load() } }
        .refreshable {
            await model.refresh()
            await load()
        }
    }

    private func load() async {
        switch await model.fetch({ try await $0.myProfile() }) {
        case .loaded(let p): page = p; failed = nil
        case .failed(let why): if page == nil { failed = why }
        case .loading: break
        }
    }

    @ViewBuilder
    private func content(_ p: MyProfile) -> some View {
        let stats = p.stats(media.wrappedValue)
        let bio = p.bio
        ProfileBanner(banner: bio.banner, avatar: pictureURL(p.profile.avatar) ?? model.account?.user.avatar,
                      name: name, fade: bio.fade) {
            HStack(spacing: 8) {
                Text(p.joinedLine).font(.system(size: 14)).foregroundStyle(.white.opacity(0.78)).lineLimit(1)
                NavigationLink(value: Route.friends) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill").font(.system(size: 11, weight: .semibold))
                        Text(p.friendsLabel).numbers()
                        if p.friends.incoming > 0 {
                            Circle().fill(Theme.brand).frame(width: 7, height: 7)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Color.black.opacity(0.35), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(p.friends.incoming > 0
                                    ? "\(p.friendsLabel), \(ProfileText.count(p.friends.incoming, "request"))"
                                    : p.friendsLabel)
            }
        }
        if !bio.text.isEmpty {
            Text(bio.text).font(.system(size: 15)).foregroundStyle(Theme.inkSoft).lineSpacing(3)
                .padding(.horizontal, Theme.pad).padding(.top, 6)
        }
        SectionHeader(title: "Statistics", chevron: false) {
            NavigationLink(value: Route.stats) { ProfileSeeAll() }.buttonStyle(.plain)
                .accessibilityLabel("See all statistics")
        }
        .padding(.top, 26)
        ProfileMediaPicker(media: media)
        ProfileStatsBlock(stats: stats) {
            Text("\(Format.grouped(stats.scored)) scored").foregroundStyle(Theme.inkMuted)
        }
        let updates = ProfileText.lastUpdates(model.library)
        if !updates.isEmpty {
            SectionHeader(title: "Last updates", chevron: false) {
                Button { openLibrary() } label: { ProfileSeeAll() }.buttonStyle(.plain)
            }
            .sectionGap(26)
            LastUpdatesShelf(updates: updates)
        }
        ProfileMoreSections(page: p)
    }

    private func openLibrary() {
        model.setPath(.library, [])
        model.tab = .library
    }
}

/// The scrolled part of your profile (42): lists, favourites, reviews, comments.
private struct ProfileMoreSections: View {
    let page: MyProfile

    @Environment(AppModel.self) private var model

    /// favourite titles: the contract's profile carries characters and names only, so the titles come from the
    /// entries you marked favourite in your library
    private var favourites: [Title] {
        model.library.filter(\.favourite).sorted { $0.updatedAt > $1.updatedAt }.map(\.title)
    }

    var body: some View {
        let lists = page.lists.lists
        let reviews = page.reviews.reviews
        let comments = page.comments.comments
        if !lists.isEmpty {
            SectionHeader(title: "Lists", chevron: false) {
                Button {
                    model.setPath(.library, [])
                    model.tab = .library
                } label: { ProfileSeeAll(text: Format.grouped(lists.count)) }
                .buttonStyle(.plain)
                .accessibilityLabel("All lists")
            }
            .sectionGap(26)
            Shelf(spacing: 14) {
                ForEach(lists) { l in
                    NavigationLink(value: Route.customList(String(l.id))) { ListMosaicCard(list: l) }
                        .buttonStyle(.plain)
                }
            }
        }
        if !favourites.isEmpty {
            SectionHeader("Favourites", chevron: false).sectionGap(26)
            Shelf(spacing: 10) {
                ForEach(favourites) { t in
                    NavigationLink(value: Route.title(t.id)) { Poster(url: t.cover, width: 76, radius: 8) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(t.name)
                }
            }
        }
        if !reviews.isEmpty {
            SectionHeader(title: "Reviews", chevron: false) {
                ProfileSeeAll(text: Format.grouped(page.reviews.total), chevron: false)
            }
            .sectionGap(26)
            VStack(spacing: 18) {
                ForEach(reviews) { r in
                    NavigationLink(value: Route.review(r.key)) { ProfileReviewRow(review: r) }.buttonStyle(.plain)
                }
            }
        }
        if !comments.isEmpty {
            SectionHeader(title: "Comments", chevron: false) {
                ProfileSeeAll(text: Format.grouped(comments.count), chevron: false)
            }
            .sectionGap(28)
            VStack(spacing: 0) {
                ForEach(Array(comments.enumerated()), id: \.element.id) { i, c in
                    NavigationLink(value: Route.user(c.author.username)) {
                        ProfileCommentRow(comment: c, separator: i < comments.count - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.pad)
        }
    }
}

/// a custom list as four covers in a square, its name and count
private struct ListMosaicCard: View {
    let list: ProfileListSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mosaic
            Text(list.name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                .padding(.top, 7)
            Text(ProfileText.count(list.count, "title")).font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                .numbers()
        }
        .frame(width: 124, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var mosaic: some View {
        let covers = list.coverURLs
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(spacing: 0) {
            HStack(spacing: 0) { cell(covers[safe: 0]); cell(covers[safe: 1]) }
            HStack(spacing: 0) { cell(covers[safe: 2]); cell(covers[safe: 3]) }
        }
        .frame(width: 124, height: 124)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.keyline, lineWidth: 0.5))
    }

    private func cell(_ url: URL?) -> some View {
        Artwork(url: url).frame(width: 62, height: 62)
    }
}

/// one of your reviews: cover, title with your score, two lines, likes and date (reviews have no headline in the
/// contract, so the text starts right under the title)
private struct ProfileReviewRow: View {
    let review: Review

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Poster(url: review.title.card.cover, width: 52, radius: 7, flat: true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(review.title.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let s = scoreText(review.score) { ScoreLabel(value: s, size: 14) }
                }
                Text(review.body).font(.system(size: 14)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 3)
                HStack(spacing: 16) {
                    Label(Format.grouped(review.likes), systemImage: "heart")
                        .labelStyle(TightLabelStyle())
                    Text(Format.shortDay(review.date))
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .numbers()
                .padding(.top, 7)
            }
        }
        .padding(.horizontal, Theme.pad)
        .contentShape(Rectangle())
    }
}

/// a comment someone left you
private struct ProfileCommentRow: View {
    let comment: ProfileComment
    var separator = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(url: comment.author.avatar, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(comment.author.username).fontWeight(.semibold).foregroundStyle(Theme.ink)
                    Text("· " + Format.agoLong(comment.date)).foregroundStyle(Theme.inkMuted)
                }
                .font(.system(size: 14))
                .lineLimit(1)
                Text(comment.body).font(.system(size: 15)).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { if separator { Hairline() } }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
