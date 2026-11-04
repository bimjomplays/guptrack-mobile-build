import SwiftUI

/// The Social tab (44, 46, 51): the large title "Social" with Activity · Friends · Messages under it. Activity is the
/// friends' feed (GET feed), Friends the same list as FriendsView (GET friends), Messages the conversations (GET
/// messages). The red count on Messages (and on the tab) is the conversations with something unread, read when the
/// tab first appears.
struct SocialView: View {
    @Environment(AppModel.self) private var model
    @State private var segment: SocialSegment = .activity
    @State private var feed: Load<[FeedLine]> = .loading
    @State private var friends: Load<FriendsState> = .loading
    @State private var messages: Load<MessageList> = .loading

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SocialSwitch(selection: $segment, unread: model.unreadMessages)
                    .padding(.horizontal, Theme.pad)
                    .padding(.top, 11)
                    .padding(.bottom, 12)
                content
            }
            .padding(.bottom, 40)
        }
        .pageBackground()
        .navigationTitle("Social")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbar }
        .task { await loadMessages() }
        .task(id: segment) { await loadIfNeeded() }
        .refreshable { await reload(segment) }
        // back from a chat or a request: what was read or answered there stays so
        .onAppear { applySession() }
    }

    private func applySession() {
        guard let l = messages.value else { return }
        let now = SocialSession.applied(l)
        if now != l { messages = .loaded(now) }
        model.unreadMessages = now.unread
    }

    @ViewBuilder private var content: some View {
        switch segment {
        case .activity:
            if let f = feed.value {
                SocialFeedList(feed: $feed.current(f))
            } else {
                SocialLoading(error: feed.error) { Task { await reload(.activity) } }
            }
        case .friends:
            if let p = friends.value {
                FriendsContent(state: $friends.current(p))
            } else {
                SocialLoading(error: friends.error) { Task { await reload(.friends) } }
            }
        case .messages:
            if let l = messages.value {
                MessagesContent(list: l)
            } else {
                SocialLoading(error: messages.error) { Task { await reload(.messages) } }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if segment == .messages {
                Button {
                    model.sheet = .newMessage
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New message")
            } else {
                Button {
                    model.sheet = .addFriend
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel("Add friend")
            }
        }
    }

    private func loadIfNeeded() async {
        switch segment {
        case .activity: if feed.value == nil { await reload(.activity) }
        case .friends: if friends.value == nil { await reload(.friends) }
        case .messages: applySession()
        }
    }

    private func reload(_ s: SocialSegment) async {
        switch s {
        case .activity: feed = await model.fetch { Feed.lines(try await $0.feed()) }
        case .friends: friends = await model.fetch { try await $0.friends() }
        case .messages: await loadMessages()
        }
    }

    private func loadMessages() async {
        let next = await model.fetch { try await $0.messageList() }
        if let l = next.value {
            messages = .loaded(l)
            applySession()
        } else if messages.value == nil {
            messages = next
        }
    }
}

// MARK: Activity (44)

/// the friends' feed: one row per thing a friend did; a row opens its thread (45)
struct SocialFeedList: View {
    @Binding var feed: [FeedLine]

    var body: some View {
        if feed.isEmpty {
            ContentUnavailableView("No activity yet", systemImage: "person.2",
                                   description: Text("What your friends watch and read shows up here."))
                .padding(.top, 40)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(feed.enumerated()), id: \.element.id) { i, item in
                    SocialFeedRow(item: item, separator: i < feed.count - 1) { feed[i] = $0 }
                }
            }
        }
    }
}

/// One activity: the friend's picture, "kenji completed Frieren", Anime · ★ 9 · 12m, a strip of posters when
/// several titles were added at once, likes and replies; the cover on the right.
struct SocialFeedRow: View {
    let item: FeedLine
    var separator = true
    var changed: (FeedLine) -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { model.open(.user(item.user.username)) } label: {
                Avatar(url: item.user.avatar, size: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.user.username)
            .padding(.top, 14)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    SocialSentence(user: item.user.username, verb: item.verb, object: item.object, tail: item.tail,
                                   size: 15)
                    meta.padding(.top, 3)
                    extra
                    if let r = item.social {
                        SocialCounts(likes: r.likes, replies: r.replies, liked: r.liked, canLike: r.canLike, like: like)
                            .padding(.top, 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let t = item.title {
                    Poster(url: t.cover, width: 46, radius: 6, flat: true)
                }
            }
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { if separator { Hairline() } }
        }
        .padding(.horizontal, Theme.pad)
        .contentShape(Rectangle())
        .onTapGesture { model.open(.activity(String(item.id))) }
        .accessibilityAction(named: "Open") { model.open(.activity(String(item.id))) }
        .contextMenu { menu }
    }

    private var meta: some View {
        HStack(spacing: 5) {
            Text(item.mediaWord)
            if let s = item.score10 {
                Text("·").opacity(0.6)
                ScoreLabel(value: s, size: 13, muted: true)
            }
            Text("·").opacity(0.6)
            Text(SocialText.feedTime(item.at))
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.inkMuted)
        .lineLimit(1)
    }

    @ViewBuilder private var extra: some View {
        let ts = item.titles
        if ts.count > 1 {
            HStack(spacing: 8) {
                ForEach(ts.prefix(5)) { t in
                    Poster(url: t.cover, width: 50, radius: 6, flat: true)
                        .onTapGesture { model.open(.title(t.id)) }
                        .accessibilityLabel(t.name)
                }
            }
            .padding(.top, 10)
        }
    }

    @ViewBuilder private var menu: some View {
        Button { model.open(.activity(String(item.id))) } label: { Label("Open", systemImage: "bubble.left") }
        if let t = item.title {
            Button { model.open(.title(t.id)) } label: { Label("Open \(t.media.singular)", systemImage: "film") }
        }
        Button { model.open(.user(item.user.username)) } label: { Label("View profile", systemImage: "person") }
    }

    private func like() {
        guard let r = item.social, r.canLike else { return }
        let before = item
        let next = item.toggledLike(me: model.socialMe)
        changed(next)
        let on = next.social?.liked ?? false
        Task {
            let answer = await model.fetch { try await $0.like(r.target, on) }
            if let fresh = answer.value {
                var l = next
                l.social = fresh
                changed(l)
            } else {
                changed(before)
            }
        }
    }
}

/// "kenji completed Frieren", "lena added 4 shows to Plan to Watch": the name and the object in bold
struct SocialSentence: View {
    let user: String
    let verb: String
    let object: String
    var tail = ""
    var size: CGFloat = 15
    var score: String?

    var body: some View {
        sentence
            .font(.system(size: size))
            .foregroundStyle(Theme.inkSoft)
            .lineSpacing(size * 0.25)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sentence: Text {
        let who = Text(user).fontWeight(.semibold).foregroundStyle(Theme.ink)
        let what = Text(object).fontWeight(.semibold).foregroundStyle(Theme.ink)
        guard let score else { return Text("\(who) \(verb) \(what)\(tail)") }
        let star = Text(Image(systemName: "star.fill")).font(.system(size: size - 3)).foregroundStyle(Theme.star)
        let n = Text(score).fontWeight(.semibold).foregroundStyle(Theme.ink)
        return Text("\(who) \(verb) \(what)\(tail) and rated it \(star) \(n)")
    }
}

// MARK: Messages (51)

/// The conversations: message requests on top, then a row per friend (unread ones bold with a blue count).
struct MessagesContent: View {
    let list: MessageList

    @Environment(AppModel.self) private var model

    var body: some View {
        LazyVStack(spacing: 0) {
            if let line = list.requestLine, let first = list.requestLines.first {
                Button { model.open(.messageRequest(first.id)) } label: { requests(line) }
                    .buttonStyle(.plain)
            }
            if list.lines.isEmpty {
                ContentUnavailableView("No messages", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Start one with the pencil above."))
                    .padding(.top, 30)
            }
            ForEach(Array(list.lines.enumerated()), id: \.element.id) { i, row in
                Button { model.open(.conversation(row.id)) } label: {
                    MessageRow(row: row, separator: i < list.lines.count - 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func requests(_ line: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 22, weight: .medium)).foregroundStyle(Theme.brandSoft)
                .frame(width: 52, height: 52)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Message requests").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(line).font(.system(size: 14)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(max(list.requests, list.requestLines.count))").font(.system(size: 15)).foregroundStyle(Theme.inkMuted).numbers()
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.inkMuted)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(Rectangle())
    }
}

/// one conversation in the list: picture, name, time, the last message, the unread count (a muted one shows a
/// bell-slash and no count)
struct MessageRow: View {
    let row: ConversationLine
    var separator = true

    var body: some View {
        let unread = row.unread > 0 && !row.muted
        HStack(spacing: 14) {
            Avatar(url: row.person.avatar, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.person.username).font(.system(size: 16, weight: unread ? .bold : .semibold))
                        .foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(row.time).font(.system(size: 13)).numbers()
                        .foregroundStyle(unread ? Theme.brandSoft : Theme.inkMuted)
                }
                HStack(spacing: 10) {
                    Text(row.preview).font(.system(size: 14)).lineLimit(1)
                        .foregroundStyle(unread ? Theme.inkSoft : Theme.inkMuted)
                    Spacer(minLength: 0)
                    if row.muted {
                        Image(systemName: "bell.slash").font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                            .accessibilityLabel("Muted")
                    } else if unread {
                        Text("\(row.unread)").font(.system(size: 12, weight: .bold)).numbers().foregroundStyle(.white)
                            .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20)
                            .background(Theme.brand, in: Capsule())
                    }
                }
            }
            .padding(.trailing, Theme.pad)
            .frame(minHeight: 76)
            .overlay(alignment: .bottom) { if separator { Hairline() } }
        }
        .padding(.leading, Theme.pad)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(unread ? String(row.unread) + " unread" : String()))
    }
}
