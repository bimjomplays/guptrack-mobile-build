import PhotosUI
import UIKit
import SwiftUI

/// A chat with a friend (52): their bubbles grey on the left, yours brand blue on the right, a time between runs,
/// shared titles as cards that open the title, reactions (long press a bubble), "typing", and the bar with + (photos,
/// share a title). The id is the friend's username. Opening it marks it read.
struct ConversationView: View {
    let id: String

    @Environment(AppModel.self) private var model
    @State private var chat: Load<Conversation> = .loading
    @State private var blocking = false

    var body: some View {
        Group {
            if let c = chat.value {
                ChatPage(chat: Binding(get: { c }, set: { chat = .loaded($0) }))
            } else {
                ScrollView { SocialLoading(error: chat.error) { Task { await load() } } }
            }
        }
        .pageBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) { header }
            ToolbarItem(placement: .topBarTrailing) { menu }
        }
        .confirmationDialog("Block \(id)?", isPresented: $blocking, titleVisibility: .visible) {
            Button("Block", role: .destructive) { block() }
        } message: {
            Text("They won't be able to message you or see your lists. They aren't told.")
        }
        .task(id: id) { if chat.value == nil { await load() } }
    }

    private var header: some View {
        Button { model.open(.user(id)) } label: {
            HStack(spacing: 9) {
                Avatar(url: chat.value?.user.avatar, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(id).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                    if let s = chat.value?.status, !s.isEmpty {
                        Text(s).font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(id), view profile")
    }

    private var menu: some View {
        Menu {
            Button { model.open(.user(id)) } label: { Label("View profile", systemImage: "person") }
            Button { model.open(.compare(id)) } label: { Label("Compare", systemImage: "arrow.left.arrow.right") }
            Button(role: .destructive) { blocking = true } label: { Label("Block", systemImage: "hand.raised") }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    private func load() async {
        chat = await model.fetch { try await $0.conversation(id) }
        guard let c = chat.value, !SocialSession.read.contains(id) else { return }
        SocialSession.read.insert(id)
        model.unreadMessages = max(0, model.unreadMessages - c.unread)
        let name = id
        _ = await model.fetch { try await $0.markRead(name) }
    }

    private func block() {
        let name = id
        Task {
            _ = await model.fetch { try await $0.block(name) }
            var p = model.path(model.tab)
            if !p.isEmpty { p.removeLast() }
            model.setPath(model.tab, p)
        }
    }
}

private struct ChatPage: View {
    @Binding var chat: Conversation

    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var choosingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var sharing = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Conversation.lines(chat.messages)) { line in
                        ChatLine(line: line) { id, emoji in chat = chat.reacting(id, emoji) }
                    }
                    if chat.typing {
                        ChatTyping(name: chat.user.username).padding(.top, 2)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.count) {
                withAnimation { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            SocialComposer(placeholder: "Message \(chat.user.username)", text: $draft, focused: $focused,
                           send: sendText) {
                Button { choosingPhoto = true } label: { Label("Photos", systemImage: "photo.on.rectangle") }
                Button { sharing = true } label: { Label("Share a title", systemImage: "film.stack") }
            }
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) {
            guard photo != nil else { return }
            photo = nil
            model.notice = "Photos can't be sent yet: the server doesn't take them in messages."
        }
        .sheet(isPresented: $sharing) {
            ChatShareTitle { title in send(SocialPost(titleId: title.id), title: title) }
        }
    }

    private func sendText() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        send(SocialPost(text: text), text: text)
    }

    private func send(_ post: SocialPost, text: String? = nil, title: Title? = nil) {
        let m = Conversation.Message(id: "new-" + UUID().uuidString, fromMe: true, text: text, title: title,
                                     at: Clock.now, reaction: nil, read: nil)
        chat = chat.sending(m)
        let name = chat.user.username
        Task { _ = await model.fetch { try await $0.sendMessage(name, post) } }
    }
}

// MARK: lines

/// a time stamp, a bubble (or a shared title) or "Read 12:03 AM"
private struct ChatLine: View {
    let line: Conversation.Line
    var react: (String, String?) -> Void

    var body: some View {
        switch line {
        case .stamp(let s):
            Text(s).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkMuted).numbers()
                .frame(maxWidth: .infinity)
                .padding(.top, 8).padding(.bottom, 8)
        case .bubble(let m, let tail):
            ChatBubble(message: m, tail: tail, react: react)
                .padding(.bottom, tail ? 12 : 3)
        case .read(let s):
            Text(s).font(.system(size: 11)).foregroundStyle(Theme.inkMuted).numbers()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 20)
                .padding(.top, -6).padding(.bottom, 10)
        }
    }
}

/// One message: text in a bubble, or a shared title's card. Long press to react.
struct ChatBubble: View {
    let message: Conversation.Message
    let tail: Bool
    var react: (String, String?) -> Void

    private var mine: Bool { message.fromMe }

    var body: some View {
        content
            .overlay(alignment: mine ? .topLeading : .topTrailing) { reaction }
            .padding(.top, message.reaction == nil ? 0 : 14)
            .contextMenu { menu }
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
            .padding(.horizontal, 16)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: !mine && tail ? 6 : 20,
                               bottomTrailingRadius: mine && tail ? 6 : 20, topTrailingRadius: 20, style: .continuous)
    }

    @ViewBuilder private var content: some View {
        if let t = message.title {
            ChatTitleCard(title: t, shape: shape)
        } else {
            Text(message.text ?? "")
                .font(.system(size: 16))
                .foregroundStyle(mine ? Color.white : Theme.ink)
                .padding(.vertical, 9).padding(.horizontal, 14)
                .background(mine ? Theme.brand : Theme.fillStrong.opacity(0.66), in: shape)
                .frame(maxWidth: 270, alignment: mine ? .trailing : .leading)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder private var reaction: some View {
        if let r = message.reaction {
            Text(r).font(.system(size: 14))
                .padding(.horizontal, 7).frame(height: 26)
                .background(Theme.raised, in: Capsule())
                .overlay(Capsule().stroke(Theme.sheet, lineWidth: 2))
                .offset(x: mine ? -12 : 12, y: -16)
                .accessibilityLabel("Reaction \(r)")
        }
    }

    @ViewBuilder private var menu: some View {
        ControlGroup {
            ForEach(Conversation.reactions.prefix(4), id: \.self) { e in
                Button(e) { react(message.id, e) }
            }
        }
        .controlGroupStyle(.compactMenu)
        Menu("More reactions") {
            ForEach(Conversation.reactions.dropFirst(4), id: \.self) { e in
                Button(e) { react(message.id, e) }
            }
        }
        if message.reaction != nil {
            Button { react(message.id, nil) } label: { Label("Remove reaction", systemImage: "xmark") }
        }
        if let text = message.text {
            Button { UIPasteboard.general.string = text } label: { Label("Copy", systemImage: "doc.on.doc") }
        }
    }
}

/// a shared title in the chat: banner, poster over its edge, name, "Anime · 11 eps · Fall 2026", your status
struct ChatTitleCard: View {
    let title: Title
    let shape: UnevenRoundedRectangle

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Artwork(url: title.banner ?? title.cover).frame(height: 104)
            HStack(alignment: .top, spacing: 12) {
                Poster(url: title.cover, width: 58, radius: 7).padding(.top, -36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(2)
                    Text(SocialText.cardLine(title)).font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                        .padding(.top, 2)
                    if let e = model.entry(title.id) {
                        StatusPillLabel(status: e.status, media: e.media, small: true, chevron: false).padding(.top, 8)
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 250)
        .background(Theme.fillStrong.opacity(0.66))
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { model.open(.title(title.id)) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the title")
    }
}

/// the three dots and "kenji is typing…"
private struct ChatTyping: View {
    let name: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Theme.inkSoft.opacity([0.75, 0.52, 0.35][i])).frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 15)
            .frame(height: 38)
            .background(Theme.fillStrong.opacity(0.66),
                        in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20,
                                                   topTrailingRadius: 20, style: .continuous))
            Text("\(name) is typing…").font(.system(size: 12)).foregroundStyle(Theme.inkMuted).padding(.bottom, 4)
            Spacer()
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

/// pick something from your list to send
private struct ChatShareTitle: View {
    var pick: (Title) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let lib = model.library
            .filter { query.isEmpty || $0.title.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.updatedAt > $1.updatedAt }
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(lib) { e in
                        Button { pick(e.title); dismiss() } label: { row(e) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .pageBackground()
            .navigationTitle("Share a title")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Your list")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ e: LibraryEntry) -> some View {
        HStack(spacing: 12) {
            Poster(url: e.title.cover, width: 40, radius: 5, flat: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(SocialText.cardLine(e.title)).font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Hairline(inset: Theme.pad + 52) }
        .contentShape(Rectangle())
    }
}

// MARK: a message request (54)

/// Someone who isn't a friend wants to message you: who they are, what they sent, then Accept / Ignore / Block and
/// Report. Accept turns this page into the conversation.
struct MessageRequestView: View {
    let id: String

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var request: Load<MessageRequest> = .loading
    @State private var confirm: Answer?

    enum Answer: String, Identifiable { case block, report; var id: String { rawValue } }

    var body: some View {
        ScrollView {
            if let r = request.value {
                content(r)
            } else {
                SocialLoading(error: request.error) { Task { await load() } }
            }
        }
        .pageBackground()
        .navigationTitle("Message request")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) { if request.value != nil { panel } }
        .confirmationDialog(dialogTitle,
                            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible, presenting: confirm) { a in
            Button(a == .block ? "Block" : "Report", role: .destructive) { finish(a.rawValue) }
        } message: { a in
            Text(verbatim: a == .block ? "They won't be able to message you or see your lists. They aren't told."
                                       : "The request goes to the server's admin, and it's taken off your list.")
        }
        .task(id: id) { if request.value == nil { await load() } }
    }

    private var dialogTitle: String { (confirm == .block ? "Block " : "Report ") + id + "?" }

    private func content(_ r: MessageRequest) -> some View {
        VStack(spacing: 0) {
            Avatar(url: r.user.avatar, size: 92)
            Text(r.user.username).font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.ink).padding(.top, 12)
            Text(r.line).font(.system(size: 14)).foregroundStyle(Theme.inkMuted).numbers().padding(.top, 3)
            Button("View profile") { model.open(.user(id)) }
                .buttonStyle(.capsule(.tone, .small))
                .padding(.top, 12)
            if let first = r.messages.first {
                Text(SocialText.stamp(first.at)).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted).numbers()
                    .padding(.top, 28).padding(.bottom, 8)
            }
            ForEach(Array(r.messages.enumerated()), id: \.element.id) { i, m in
                let last = i == r.messages.count - 1
                ChatBubble(message: m, tail: last) { _, _ in }
                    .padding(.bottom, last ? 12 : 3)
            }
        }
        .padding(.top, 16)
    }

    private var panel: some View {
        VStack(spacing: 10) {
            Text("Accept to move this to your messages. \(id) won't know you've seen it unless you reply.")
                .font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Button("Accept") { accept() }
                .buttonStyle(.capsule(.tint, .large, full: true))
            HStack(spacing: 10) {
                Button("Ignore") { finish("ignore") }
                    .buttonStyle(.capsule(.tone, .large, full: true))
                Button("Block") { confirm = .block }
                    .buttonStyle(.capsule(.tone, .large, color: Theme.danger, full: true))
            }
            Button("Report") { confirm = .report }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.danger)
                .buttonStyle(.plain)
                .padding(.top, 2)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(Theme.sheet)
        .overlay(alignment: .top) { Hairline() }
    }

    private func load() async {
        request = await model.fetch { try await $0.messageRequest(id) }
    }

    private func accept() {
        let name = id
        SocialSession.answered.insert(name)
        Task { _ = await model.fetch { try await $0.answerMessageRequest(name, "accept") } }
        var p = model.path(model.tab)
        if !p.isEmpty { p.removeLast() }
        p.append(.conversation(name))
        model.setPath(model.tab, p)
    }

    private func finish(_ answer: String) {
        let name = id
        SocialSession.answered.insert(name)
        Task {
            if answer == "block" {
                _ = await model.fetch { try await $0.block(name) }
            } else {
                _ = await model.fetch { try await $0.answerMessageRequest(name, answer) }
            }
        }
        dismiss()
    }
}

// MARK: New message

/// Pick a friend, then their conversation opens.
struct NewMessageSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var page: Load<FriendsPage> = .loading
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                if let p = page.value {
                    list(p.friends.filter { query.isEmpty || $0.user.username.localizedCaseInsensitiveContains(query)
                        || $0.user.name.localizedCaseInsensitiveContains(query) })
                } else {
                    SocialLoading(error: page.error) { Task { await load() } }
                }
            }
            .pageBackground()
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Friends")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
            .task { if page.value == nil { await load() } }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder private func list(_ friends: [FriendsPage.Friend]) -> some View {
        if friends.isEmpty {
            Text(query.isEmpty ? "Add friends to message them." : "No friend called \(query).")
                .font(.system(size: 15)).foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity).padding(.vertical, 40)
        }
        LazyVStack(spacing: 0) {
            ForEach(Array(friends.enumerated()), id: \.element.id) { i, f in
                Button { open(f.id) } label: {
                    SocialPersonRow(user: f.user, line: f.seen, online: f.online, separator: i < friends.count - 1) {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    private func open(_ username: String) {
        model.sheet = nil
        model.tab = .social
        model.open(.conversation(username))
    }

    private func load() async {
        page = await model.fetch { try await $0.friendsPage() }
    }
}
