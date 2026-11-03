import SwiftUI

/// One activity with its replies (45): who did what, the title card with your own status, who liked it, the
/// replies, and a reply bar at the foot.
struct ActivityView: View {
    let id: String

    @Environment(AppModel.self) private var model
    @State private var thread: Load<ActivityThread> = .loading

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
                    if let item = thread.value?.item {
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
        thread = await model.fetch { try await $0.activityThread(id) }
    }
}

private struct ActivityThreadPage: View {
    @Binding var thread: ActivityThread

    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var item: ActivityFeed.Item { thread.item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                SocialSentence(user: item.user.username, verb: item.verb, object: item.object, size: 17,
                               score: item.ratedInThread ? item.score10 : nil)
                    .padding(.horizontal, Theme.pad)
                    .padding(.top, 12)
                if let q = item.quote {
                    Text(q).font(.system(size: 16)).foregroundStyle(Theme.inkSoft).lineSpacing(3)
                        .padding(.horizontal, Theme.pad).padding(.top, 10)
                }
                if let t = item.title {
                    SocialTitleCard(title: t).padding(.top, 14)
                }
                if let ts = item.titles, !ts.isEmpty { strip(ts) }
                SocialLikedBy(users: thread.likedBy, likes: item.likes, liked: item.liked, like: like)
                SocialReplies(replies: $thread.replies, kind: .activity) { draft = "@\($0) "; focused = true }
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
            if let t = await model.fetch({ try await $0.activityThread(thread.item.id) }).value { thread = t }
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
        thread.item = item.toggledLike()
        let me = model.socialMe
        if thread.item.liked { thread.likedBy.insert(me, at: 0) } else { thread.likedBy.removeAll { $0 == me } }
        let id = item.id, on = thread.item.liked
        Task { _ = await model.fetch { try await $0.likeActivity(id, on) } }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        thread.replies.append(SocialReplies.mine(text, model.socialMe))
        thread.item.replies += 1
        let id = item.id
        Task { _ = await model.fetch { try await $0.replyToActivity(id, text) } }
    }
}

// MARK: shared by activity and review threads

/// "2 replies" and the replies under it; Reply puts @name in the bar
struct SocialReplies: View {
    @Binding var replies: [ActivityThread.Reply]
    let kind: Kind
    var answer: (String) -> Void

    enum Kind { case activity, review }

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(replies.isEmpty ? "No replies yet" : SocialText.repliesHeading(replies.count))
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, Theme.pad)
                .padding(.top, 14)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(replies.enumerated()), id: \.element.id) { i, r in
                SocialReplyRow(reply: r, separator: i < replies.count - 1, like: { like(i) }, answer: { answer(r.user.username) })
            }
        }
    }

    private func like(_ i: Int) {
        replies[i] = replies[i].toggledLike()
    }

    /// a reply you just wrote
    static func mine(_ text: String, _ me: UserRef) -> ActivityThread.Reply {
        ActivityThread.Reply(id: "new-" + UUID().uuidString, user: me, text: text, at: Clock.now, likes: 0, liked: false)
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
