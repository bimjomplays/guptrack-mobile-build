import SwiftUI

/// One activity with its replies (45): who did what, the title card with your own status, who liked it, the
/// replies, and a reply bar at the foot. GET activity/:id for the line, GET replies/activity/:id for the replies and
/// the likes.
struct ActivityView: View {
    let id: String

    @Environment(AppModel.self) private var model
    @State private var thread: Load<ActivityThreadState> = .loading

    var body: some View {
        Group {
            if let t = thread.value {
                ActivityThreadPage(thread: Binding(get: { t }, set: { thread = .loaded($0) }))
            } else {
                ScrollView { SocialLoading(error: thread.error) { Task { await load() } } }
            }
        }
        .pageBackground()
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let item = thread.value?.line {
                        Button { model.open(.user(item.user.username)) } label: {
                            Label("View \(item.user.username)", systemImage: "person")
                        }
                        if let t = item.title {
                            Button { model.open(.title(t.id)) } label: { Label("Open \(t.name)", systemImage: "film") }
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
        guard let n = Int(id) else {
            thread = .failed("This activity doesn't exist.")
            return
        }
        thread = await model.fetch { try await ActivityThreadState.load(n, $0) }
    }
}

/// the line, its likes and its replies
struct ActivityThreadState: Hashable, Sendable {
    var line: FeedLine
    var reactions: Reactions
    var replies: [Reply]

    static func load(_ id: Int, _ api: APIClient) async throws -> ActivityThreadState {
        let item = try await api.activity(id)
        guard let line = Feed.lines([item]).first else { throw APIError.server(404, "not_found", "This activity is gone.") }
        let target = line.social?.target ?? Reactions.Target(on: "activity", id: id)
        let r = try await api.replies(target)
        return ActivityThreadState(line: line, reactions: r.reactions, replies: r.replies)
    }
}

private struct ActivityThreadPage: View {
    @Binding var thread: ActivityThreadState

    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var parent: Int?
    @FocusState private var focused: Bool

    private var item: FeedLine { thread.line }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                SocialSentence(user: item.user.username, verb: item.verb, object: item.object, tail: item.tail,
                               size: 17, score: item.score10)
                    .padding(.horizontal, Theme.pad)
                    .padding(.top, 12)
                if let t = item.title {
                    SocialTitleCard(title: t).padding(.top, 14)
                }
                if item.titles.count > 1 { strip(item.titles) }
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
            SocialComposer(placeholder: "Reply to \(item.user.username)", text: $draft, focused: $focused, send: send) {
                SocialMentionMenu(text: $draft)
            }
        }
        .refreshable {
            if let t = await model.fetch({ try await ActivityThreadState.load(item.id, $0) }).value { thread = t }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Avatar(url: item.user.avatar, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.user.username).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(SocialText.agoWords(item.at)).font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.pad)
        .contentShape(Rectangle())
        .onTapGesture { model.open(.user(item.user.username)) }
    }

    private func strip(_ ts: [Title]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ts) { t in
                    Button { model.open(.title(t.id)) } label: { Poster(url: t.cover, width: 84, radius: 8) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(t.name)
                }
            }
            .padding(.horizontal, Theme.pad)
        }
        .padding(.top, 14)
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

// MARK: shared by activity and review threads

/// "2 replies" and the replies under it; Reply puts @name in the bar and answers that reply's thread
struct SocialReplies: View {
    @Binding var replies: [Reply]
    /// the username and the top-level reply the answer belongs to
    var answer: (String, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(replies.isEmpty ? "No replies yet" : SocialText.repliesHeading(replies.count))
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, Theme.pad)
                .padding(.top, 14)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(replies.enumerated()), id: \.element.id) { i, r in
                SocialReplyRow(reply: r, separator: i < replies.count - 1) { answer(r.author.username, r.parent ?? r.id) }
            }
        }
    }

    /// a reply you just wrote, shown at once (a negative id until the page reloads)
    static func mine(_ text: String, parent: Int? = nil, _ me: Person) -> Reply {
        Reply(id: -Int.random(in: 1...Int(Int32.max)), parent: parent, author: me, body: text,
              at: Int64(Clock.now.timeIntervalSince1970 * 1000), edited: nil, canEdit: true, canDelete: true)
    }
}

/// the + in a reply bar: mention something from your list
struct SocialMentionMenu: View {
    @Binding var text: String

    @Environment(AppModel.self) private var model

    var body: some View {
        let recent = model.library.sorted { $0.updatedAt > $1.updatedAt }.prefix(6)
        Section("Mention a title") {
            ForEach(Array(recent)) { e in
                Button(e.title.name) {
                    text += (text.isEmpty || text.hasSuffix(" ") ? "" : " ") + e.title.name + " "
                }
            }
        }
    }
}
