import SwiftUI

/// A title's reviews (50): the average on top, the sort and filter chips, then each review (score, headline, a few
/// lines, likes) with Read review. Write a review from the toolbar.
struct ReviewsView: View {
    let titleId: String

    @Environment(AppModel.self) private var model
    @State private var page: Load<ReviewsPage> = .loading

    var body: some View {
        Group {
            if let p = page.value {
                ReviewsList(page: Binding(get: { p }, set: { page = .loaded($0) }))
            } else {
                ScrollView { SocialLoading(error: page.error) { Task { await load() } } }
            }
        }
        .pageBackground()
        .navigationTitle("Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.sheet = .writeReview(titleId)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Write a review")
            }
        }
        .task(id: titleId) { if page.value == nil { await load() } }
        .refreshable { await load() }
    }

    private func load() async {
        page = await model.fetch { try await $0.reviewsPage(titleId) }
    }
}

private struct ReviewsList: View {
    @Binding var page: ReviewsPage

    @Environment(AppModel.self) private var model
    @State private var sort: ReviewsPage.Sort = .liked
    @State private var friendsOnly = false
    @State private var nearMine = false
    @State private var spoilers = false

    private var myScore: Int? { model.entry(page.title.id)?.score }

    var body: some View {
        let shown = ReviewsPage.shown(page.reviews, sort: sort, friendsOnly: friendsOnly,
                                      nearScore: nearMine ? myScore : nil, spoilers: spoilers)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                chips
                Hairline().padding(.top, 8)
                if shown.isEmpty {
                    Text(page.reviews.isEmpty ? "No reviews yet. Be the first." : "No reviews match these filters.")
                        .font(.system(size: 15)).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, r in
                    ReviewRow(review: r, separator: i < shown.count - 1) { like(r.id) }
                }
            }
            .padding(.bottom, 40)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Poster(url: page.title.cover, width: 52, radius: 7)
            VStack(alignment: .leading, spacing: 4) {
                Text(page.title.name).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                HStack(spacing: 8) {
                    ScoreLabel(value: Format.average(page.average), size: 15)
                    Text(page.averageLine).font(.system(size: 14)).foregroundStyle(Theme.inkMuted).numbers()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .contentShape(Rectangle())
        .onTapGesture { model.open(.title(page.title.id)) }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(ReviewsPage.Sort.allCases) { s in Text(s.label).tag(s) }
                    }
                } label: {
                    ChipLabel(text: sort.label, on: true, menu: true)
                }
                .accessibilityLabel("Sort: \(sort.label)")
                Button { friendsOnly.toggle() } label: {
                    ChipLabel(text: "Friends", on: friendsOnly, count: "\(page.friendCount)")
                }
                if let mine = myScore {
                    Button { nearMine.toggle() } label: {
                        ChipLabel(text: "Your score ★\(Format.score10(mine))", on: nearMine)
                    }
                    .accessibilityLabel("Near your score")
                }
                Button { spoilers.toggle() } label: {
                    ChipLabel(text: "Spoilers", on: spoilers, symbol: spoilers ? "eye" : nil)
                }
                .accessibilityLabel(spoilers ? "Hide spoilers" : "Show spoilers")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.pad)
        }
        .padding(.bottom, 6)
    }

    private func like(_ id: String) {
        guard let i = page.reviews.firstIndex(where: { $0.id == id }) else { return }
        page.reviews[i] = page.reviews[i].toggledLike()
        let on = page.reviews[i].liked
        Task { _ = await model.fetch { try await $0.likeReview(id, on) } }
    }
}

/// one review in the list: who, when, the score, the headline, three lines, likes, Read review
struct ReviewRow: View {
    let review: ReviewsPage.Review
    var separator = true
    var like: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReviewByline(review: review, size: 34)
            Text(review.headline).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                .padding(.top, 11)
            Text(review.body).font(.system(size: 15)).foregroundStyle(Theme.inkSoft)
                .lineSpacing(2).lineLimit(3)
                .padding(.top, 3)
            HStack(spacing: 0) {
                SocialCounts(likes: review.likes, replies: review.replies, liked: review.liked, like: like)
                Spacer()
                Button("Read review") { model.open(.review(review.id)) }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.brandSoft)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Read \(review.user.username)’s review")
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { if separator { Hairline() } }
        .contentShape(Rectangle())
        .onTapGesture { model.open(.review(review.id)) }
    }
}

/// [avatar] kenji (Friend) / 12 minutes ago ............ ★ 9
struct ReviewByline: View {
    let review: ReviewsPage.Review
    var size: CGFloat = 34

    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Button { model.open(.user(review.user.username)) } label: { Avatar(url: review.user.avatar, size: size) }
                .buttonStyle(.plain)
                .accessibilityLabel(review.user.username)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(review.user.username).font(.system(size: size > 40 ? 16 : 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    if review.friend {
                        Text("Friend").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.brandSoft)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.brand.opacity(0.16), in: Capsule())
                    }
                    if review.spoiler {
                        Text("Spoilers").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.danger)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.danger.opacity(0.16), in: Capsule())
                    }
                }
                Text(SocialText.agoWords(review.at)).font(.system(size: size > 40 ? 13 : 12)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 8)
            ScoreLabel(value: review.score10, size: 16)
        }
    }
}

// MARK: one review (laid out like 45)

/// One review with its replies: the byline, the headline and the whole text (hidden behind a tap when it has
/// spoilers), the title card, who liked it, the replies and a reply bar.
struct ReviewView: View {
    let id: String

    @Environment(AppModel.self) private var model
    @State private var thread: Load<ReviewThread> = .loading

    var body: some View {
        Group {
            if let t = thread.value {
                ReviewThreadPage(thread: Binding(get: { t }, set: { thread = .loaded($0) }))
            } else {
                ScrollView { SocialLoading(error: thread.error) { Task { await load() } } }
            }
        }
        .pageBackground()
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let t = thread.value {
                        Button { model.open(.user(t.review.user.username)) } label: {
                            Label("View \(t.review.user.username)", systemImage: "person")
                        }
                        Button { model.open(.reviews(t.title.id)) } label: {
                            Label("All reviews", systemImage: "text.bubble")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .task(id: id) { if thread.value == nil { await load() } }
    }

    private func load() async {
        thread = await model.fetch { try await $0.reviewThread(id) }
    }
}

private struct ReviewThreadPage: View {
    @Binding var thread: ReviewThread

    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var reveal = false
    @FocusState private var focused: Bool

    private var review: ReviewsPage.Review { thread.review }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ReviewByline(review: review, size: 44).padding(.horizontal, Theme.pad)
                Text(review.headline).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, Theme.pad).padding(.top, 14)
                text.padding(.top, 8)
                SocialTitleCard(title: thread.title).padding(.top, 16)
                SocialLikedBy(users: thread.likedBy, likes: review.likes, liked: review.liked, like: like)
                SocialReplies(replies: $thread.replies, kind: .review) { draft = "@\($0) "; focused = true }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            SocialComposer(placeholder: "Reply to \(review.user.username)", text: $draft, focused: $focused, send: send) {
                SocialMentionMenu(text: $draft)
            }
        }
    }

    @ViewBuilder private var text: some View {
        if review.spoiler && !reveal {
            Button { reveal = true } label: {
                Label("This review has spoilers. Show it", systemImage: "eye.slash")
            }
            .buttonStyle(.capsule(.tone, .small))
            .padding(.horizontal, Theme.pad)
        } else {
            Text(review.body).font(.system(size: 16)).foregroundStyle(Theme.inkSoft).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.pad)
                .textSelection(.enabled)
        }
    }

    private func like() {
        thread.review = review.toggledLike()
        let me = model.socialMe
        if thread.review.liked { thread.likedBy.insert(me, at: 0) } else { thread.likedBy.removeAll { $0 == me } }
        let id = review.id, on = thread.review.liked
        Task { _ = await model.fetch { try await $0.likeReview(id, on) } }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        thread.replies.append(SocialReplies.mine(text, model.socialMe))
        thread.review.replies += 1
        let id = review.id
        Task { _ = await model.fetch { try await $0.replyToReview(id, text) } }
    }
}
