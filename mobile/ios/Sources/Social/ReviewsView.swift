import SwiftUI

/// A title's reviews (50, GET titles/:kind/:id/reviews): the average on top, the sort and filter chips, then each
/// review (score, a few lines, likes) with Read review. Yours comes first. Write a review from the toolbar.
struct ReviewsView: View {
    let titleId: String

    @Environment(AppModel.self) private var model
    @State private var page: Load<TitleReviews> = .loading

    var body: some View {
        Group {
            if let p = page.value {
                ReviewsList(titleId: titleId, page: Binding(get: { p }, set: { page = .loaded($0) }))
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
        page = await model.fetch { try await $0.titleReviews(titleId) }
    }
}

private struct ReviewsList: View {
    let titleId: String
    @Binding var page: TitleReviews

    @Environment(AppModel.self) private var model
    @State private var sort: TitleReviews.Sort = .liked
    @State private var friendsOnly = false
    @State private var nearMine = false
    @State private var spoilers = false

    private var myScore: Int? { model.entry(titleId)?.score }

    /// the title: from the reviews themselves, else from your library
    private var title: Title? { page.title?.card ?? model.entry(titleId)?.title }

    var body: some View {
        let others = TitleReviews.shown(page.reviews, sort: sort, friendsOnly: friendsOnly,
                                        nearScore: nearMine ? myScore : nil, spoilers: spoilers)
        let shown = (page.mine.map { [$0] } ?? []) + others
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                chips
                Hairline().padding(.top, 8)
                if shown.isEmpty {
                    Text(page.all.isEmpty ? "No reviews yet. Be the first." : "No reviews match these filters.")
                        .font(.system(size: 15)).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, r in
                    ReviewRow(review: r, separator: i < shown.count - 1) { like(r) }
                }
            }
            .padding(.bottom, 40)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Poster(url: title?.cover, width: 52, radius: 7)
            VStack(alignment: .leading, spacing: 4) {
                Text(title?.name ?? "Reviews").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let a = page.average { ScoreLabel(value: Format.average(a), size: 15) }
                    Text(page.averageLine).font(.system(size: 14)).foregroundStyle(Theme.inkMuted).numbers()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .contentShape(Rectangle())
        .onTapGesture { model.open(.title(titleId)) }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(TitleReviews.Sort.allCases) { s in Text(s.label).tag(s) }
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

    private func like(_ r: Review) {
        guard let social = r.social, social.canLike else { return }
        let next = r.toggledLike(me: model.socialMe)
        page = page.replacing(next)
        let on = next.social?.liked ?? false
        Task {
            let answer = await model.fetch { try await $0.like(social.target, on) }
            var done = next
            done.social = answer.value ?? social
            page = page.replacing(done)
        }
    }
}

/// one review in the list: who, when, the score, three lines, likes, Read review
struct ReviewRow: View {
    let review: Review
    var separator = true
    var like: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReviewByline(review: review, size: 34)
            Text(review.body).font(.system(size: 15)).foregroundStyle(Theme.inkSoft)
                .lineSpacing(2).lineLimit(3)
                .padding(.top, 11)
            HStack(spacing: 0) {
                if let r = review.social {
                    SocialCounts(likes: r.likes, replies: r.replies, liked: r.liked, canLike: r.canLike, like: like)
                }
                Spacer()
                Button("Read review") { model.open(.review(review.key)) }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.brandSoft)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Read \(review.author.username)’s review")
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { if separator { Hairline() } }
        .contentShape(Rectangle())
        .onTapGesture { model.open(.review(review.key)) }
    }
}

/// [avatar] kenji (Friend) / 12 minutes ago ............ ★ 9
struct ReviewByline: View {
    let review: Review
    var size: CGFloat = 34

    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Button { model.open(.user(review.author.username)) } label: { Avatar(url: review.author.avatar, size: size) }
                .buttonStyle(.plain)
                .accessibilityLabel(review.author.username)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(review.author.username).font(.system(size: size > 40 ? 16 : 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    if review.author.isFriend {
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
                Text(SocialText.agoWords(review.date)).font(.system(size: size > 40 ? 13 : 12)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 8)
            if let s = review.score10 { ScoreLabel(value: s, size: 16) }
        }
    }
}

// MARK: one review (laid out like 45)

/// One review with its replies (GET users/:username/reviews/:kind/:id, then GET replies/review/:id): the byline,
/// the whole text (hidden behind a tap when it has spoilers), the title card, who liked it, the replies and a reply
/// bar. `id` is the review's key, "anime:154587@kenji".
struct ReviewView: View {
    let id: String

    @Environment(AppModel.self) private var model
    @State private var thread: Load<ReviewThreadState> = .loading

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
                        Button { model.open(.user(t.review.author.username)) } label: {
                            Label("View \(t.review.author.username)", systemImage: "person")
                        }
                        Button { model.open(.reviews(t.review.title.titleId)) } label: {
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
        guard let key = ReviewKey(id) else {
            thread = .failed("This review doesn't exist.")
            return
        }
        thread = await model.fetch { try await ReviewThreadState.load(key, $0) }
    }
}

/// a review, its likes and its replies
struct ReviewThreadState: Hashable, Sendable {
    var review: Review
    var reactions: Reactions
    var replies: [Reply]

    static func load(_ key: ReviewKey, _ api: APIClient) async throws -> ReviewThreadState {
        let review = try await api.review(key)
        let r = try await api.replies(review.social?.target ?? Reactions.Target(on: "review", id: review.id))
        return ReviewThreadState(review: review, reactions: r.reactions, replies: r.replies)
    }
}

private struct ReviewThreadPage: View {
    @Binding var thread: ReviewThreadState

    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var parent: Int?
    @State private var reveal = false
    @FocusState private var focused: Bool

    private var review: Review { thread.review }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ReviewByline(review: review, size: 44).padding(.horizontal, Theme.pad)
                text.padding(.top, 14)
                SocialTitleCard(title: model.entry(review.title.titleId)?.title ?? review.title.card).padding(.top, 16)
                SocialLikedBy(reactions: thread.reactions, like: like)
                SocialReplies(replies: $thread.replies) { name, id in
                    draft = "@\(name) "
                    parent = id
                    focused = true
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            SocialComposer(placeholder: "Reply to \(review.author.username)", text: $draft, focused: $focused,
                           send: send) {
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
        let before = thread.reactions
        guard before.canLike else { return }
        thread.reactions = before.toggledLike(me: model.socialMe)
        let target = before.target, on = thread.reactions.liked
        Task {
            let r = await model.fetch { try await $0.like(target, on) }
            thread.reactions = r.value ?? before
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        let local = SocialReplies.mine(text, parent: parent, model.socialMe)
        let answering = parent
        parent = nil
        thread.replies.append(local)
        thread.reactions.replies += 1
        let target = thread.reactions.target
        Task {
            if await model.fetch({ try await $0.reply(target, text, parent: answering) }).value == nil {
                thread.replies.removeAll { $0.id == local.id }
                thread.reactions.replies = max(0, thread.reactions.replies - 1)
            }
        }
    }
}
