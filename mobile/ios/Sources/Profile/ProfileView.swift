import SwiftUI

/// Your profile, the Profile tab (41, 42): your banner, picture and bio; your numbers per media from the offline
/// library; last updates; then your lists, favourites, reviews and the comments people left you. Editing happens in
/// Settings › Profile (the gear), so there's no Edit button here; friends is a small link by your name.
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var page: ProfilePage?
    @State private var lists: [CustomList] = []
    @State private var failed: String?
    @State private var scrolled = false
    @AppStorage(MediaKind.profileKey) private var mediaRaw = MediaKind.anime.rawValue

    private var media: Binding<MediaKind> {
        Binding(get: { MediaKind(rawValue: mediaRaw) ?? .anime }, set: { mediaRaw = $0.rawValue })
    }

    private var name: String { page?.user.name ?? model.account?.user.name ?? "Profile" }

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
                ShareLink(item: Route.user(page?.user.username ?? model.account?.user.username ?? "").url) {
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
        switch await model.fetch({ try await $0.profilePage() }) {
        case .loaded(let p): page = p; failed = nil
        case .failed(let why): if page == nil { failed = why }
        case .loading: break
        }
        if let l = await model.fetch({ try await $0.customLists() }).value { lists = l }
    }

    @ViewBuilder
    private func content(_ p: ProfilePage) -> some View {
        let stats = LibraryStats(model.library, media: media.wrappedValue)
        ProfileBanner(banner: p.banner, avatar: p.user.avatar, name: p.user.name, fade: p.fade) {
            HStack(spacing: 8) {
                Text(p.joinedLine).font(.system(size: 14)).foregroundStyle(.white.opacity(0.78)).lineLimit(1)
                NavigationLink(value: Route.friends) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill").font(.system(size: 11, weight: .semibold))
                        Text(p.friendsLabel).numbers()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Color.black.opacity(0.35), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(p.friendsLabel)
            }
        }
        if !p.bio.isEmpty {
            Text(p.bio).font(.system(size: 15)).foregroundStyle(Theme.inkSoft).lineSpacing(3)
                .padding(.horizontal, Theme.pad).padding(.top, 6)
        }
        SectionHeader(title: "Statistics", chevron: false) {
            NavigationLink(value: Route.stats) { ProfileSeeAll() }.buttonStyle(.plain)
                .accessibilityLabel("See all statistics")
        }
        .padding(.top, 26)
        ProfileMediaPicker(media: media)
        ProfileStatsBlock(summary: stats.summary) {
            Text("\(Format.grouped(stats.summary.scored)) scored").foregroundStyle(Theme.inkMuted)
        }
        let updates = ProfileText.lastUpdates(model.library)
        if !updates.isEmpty {
            SectionHeader(title: "Last updates", chevron: false) {
                Button { openLibrary() } label: { ProfileSeeAll() }.buttonStyle(.plain)
            }
            .sectionGap(26)
            LastUpdatesShelf(updates: updates)
        }
        ProfileMoreSections(page: p, lists: lists)
    }

    private func openLibrary() {
        model.setPath(.library, [])
        model.tab = .library
    }
}

/// The scrolled part of your profile (42): lists, favourites, reviews, comments.
private struct ProfileMoreSections: View {
    let page: ProfilePage
    let lists: [CustomList]

    @Environment(AppModel.self) private var model

    var body: some View {
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
                    NavigationLink(value: Route.customList(l.id)) { ListMosaicCard(list: l) }
                        .buttonStyle(.plain)
                }
            }
        }
        if !page.favourites.isEmpty {
            SectionHeader("Favourites", chevron: false).sectionGap(26)
            Shelf(spacing: 10) {
                ForEach(page.favourites) { t in
                    NavigationLink(value: Route.title(t.id)) { Poster(url: t.cover, width: 76, radius: 8) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(t.name)
                }
            }
        }
        if !page.reviews.isEmpty {
            SectionHeader(title: "Reviews", chevron: false) {
                ProfileSeeAll(text: Format.grouped(page.reviewCount), chevron: false)
            }
            .sectionGap(26)
            VStack(spacing: 18) {
                ForEach(page.reviews) { r in
                    NavigationLink(value: Route.review(r.id)) { ProfileReviewRow(review: r) }.buttonStyle(.plain)
                }
            }
        }
        if !page.comments.isEmpty {
            SectionHeader(title: "Comments", chevron: false) {
                ProfileSeeAll(text: Format.grouped(page.commentCount), chevron: false)
            }
            .sectionGap(28)
            VStack(spacing: 0) {
                ForEach(Array(page.comments.enumerated()), id: \.element.id) { i, c in
                    NavigationLink(value: Route.user(c.user.username)) {
                        ProfileCommentRow(comment: c, separator: i < page.comments.count - 1)
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
    let list: CustomList

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mosaic
            Text(list.name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                .padding(.top, 7)
            Text(ProfileText.count(list.items.count, "title")).font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                .numbers()
        }
        .frame(width: 124, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var mosaic: some View {
        let covers = list.covers
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

/// one of your reviews: cover, title with your score, headline, two lines, likes and date
private struct ProfileReviewRow: View {
    let review: ProfilePage.Review

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Poster(url: review.title.cover, width: 52, radius: 7, flat: true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(review.title.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let s = scoreText(review.score) { ScoreLabel(value: s, size: 14) }
                }
                Text(review.headline).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                    .padding(.top, 3)
                Text(review.body).font(.system(size: 14)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 2)
                HStack(spacing: 16) {
                    Label(Format.grouped(review.likes), systemImage: "heart")
                        .labelStyle(TightLabelStyle())
                    Text(Format.shortDay(review.at))
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
    let comment: ProfilePage.Comment
    var separator = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(url: comment.user.avatar, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(comment.user.username).fontWeight(.semibold).foregroundStyle(Theme.ink)
                    Text("· " + Format.agoLong(comment.at)).foregroundStyle(Theme.inkMuted)
                }
                .font(.system(size: 14))
                .lineLimit(1)
                Text(comment.text).font(.system(size: 15)).foregroundStyle(Theme.ink)
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
