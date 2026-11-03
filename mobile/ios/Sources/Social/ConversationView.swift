import PhotosUI
import UIKit
import SwiftUI

/// A chat (52, GET conversations/:username): their bubbles grey on the left, yours brand blue on the right, a time
/// between runs, shared titles as cards that open the title, photos, reactions (long press a bubble), "typing" (from
/// GET messages/pulse while the chat is open), and the bar with + (photos, share a title). The id is their username.
/// Opening it marks it read.
struct ConversationView: View {
    let id: String

    @Environment(AppModel.self) private var model
    @State private var chat: Load<Conversation> = .loading
    @State private var typing = false
    @State private var blocking = false

    var body: some View {
        Group {
            if let c = chat.value {
                ChatPage(chat: Binding(get: { c }, set: { chat = .loaded($0) }), typing: typing)
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
        .task(id: id) { await watchTyping() }
    }

    private var header: some View {
        Button { model.open(.user(id)) } label: {
            HStack(spacing: 9) {
                Avatar(url: chat.value?.person.avatar, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(id).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                    if typing {
                        Text("typing…").font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                    } else if chat.value?.muted == true {
                        Text("Muted").font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
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
            if let c = chat.value {
                Button { mute(!c.muted) } label: {
                    Label(c.muted ? "Unmute" : "Mute", systemImage: c.muted ? "bell" : "bell.slash")
                }
            }
            Button(role: .destructive) { blocking = true } label: { Label("Block", systemImage: "hand.raised") }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    private func load() async {
        chat = await model.fetch { try await $0.conversation(id) }
        guard chat.value != nil, !SocialSession.read.contains(id) else { return }
        SocialSession.read.insert(id)
        let name = id
        _ = await model.fetch { try await $0.markRead(name) }
        if let l = await model.fetch({ try await $0.messageList() }).value {
            model.unreadMessages = SocialSession.applied(l).unread
        }
    }

    /// "typing" comes from the pulse (the live stream isn't held open by the app yet); asked every few seconds
    private func watchTyping() async {
        while !Task.isCancelled {
            if let p = try? await model.api.pulse() { typing = p.typing.contains(id) }
            try? await Task.sleep(for: .seconds(4))
        }
    }

    private func mute(_ on: Bool) {
        guard var c = chat.value else { return }
        c.muted = on
        chat = .loaded(c)
        let name = id
        Task {
            if await model.fetch({ try await $0.mute(name, on) }).value == nil, var back = chat.value {
                back.muted = !on
                chat = .loaded(back)
            }
        }
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
    let typing: Bool

    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var choosingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var sharing = false
    @FocusState private var focused: Bool

    private var name: String { chat.person.username }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(chat.lines()) { line in
                        ChatLine(line: line) { id, emoji in react(id, emoji) }
                    }
                    if typing {
                        ChatTyping(name: name).padding(.top, 2)
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
            if chat.canSend {
                SocialComposer(placeholder: "Message \(name)", text: $draft, focused: $focused, send: sendText) {
                    Button { choosingPhoto = true } label: { Label("Photos", systemImage: "photo.on.rectangle") }
                    Button { sharing = true } label: { Label("Share a title", systemImage: "film.stack") }
                }
            } else {
                Text(chat.why ?? "You can't message \(name).")
                    .font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Theme.pad)
                    .padding(.vertical, 14)
                    .background(Theme.sheet)
                    .overlay(alignment: .top) { Hairline() }
            }
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) {
            guard let item = photo else { return }
            photo = nil
            sendPhoto(item)
        }
        .sheet(isPresented: $sharing) {
            ChatShareTitle { title in sendTitle(title) }
        }
    }

    private func sendText() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        send(OutgoingMessage(body: text), shown: local(body: text))
    }

    private func sendTitle(_ title: Title) {
        guard let k = TitleKey(titleId: title.id) else { return }
        let card = Card(kind: title.media, id: k.id, title: title.name, cover: title.cover?.absoluteString ?? "",
                        format: title.format ?? "", year: title.year, status: nil, score: nil)
        send(OutgoingMessage(card: .init(kind: title.media, id: k.id, mine: false)), shown: local(card: card))
    }

    /// uploads the picked photo (as JPEG), then sends it
    private func sendPhoto(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) else {
                model.notice = "That photo couldn't be read."
                return
            }
            guard let p = await model.fetch({ try await $0.uploadPhoto(jpeg, contentType: "image/jpeg") }).value else { return }
            send(OutgoingMessage(photos: [p.name]), shown: local(photos: [p]))
        }
    }

    /// your message as it shows until the chat reloads (an id above any real one, so it sorts last)
    private func local(body: String = "", card: Card? = nil, photos: [Photo] = []) -> Message {
        let next = (chat.messages.map(\.id).max() ?? 0) + 1_000_000
        return Message(id: next, mine: true, body: body, card: card, photos: photos,
                       at: Int64(Clock.now.timeIntervalSince1970 * 1000), edited: nil, deleted: false, reactions: [])
    }

    private func send(_ out: OutgoingMessage, shown: Message) {
        chat = chat.sending(shown)
        let to = name, requestId = UUID().uuidString
        Task {
            if await model.fetch({ try await $0.sendMessage(to, out, requestId: requestId) }).value == nil {
                chat.messages.removeAll { $0.id == shown.id }
            }
        }
    }

    private func react(_ id: Int, _ emoji: String?) {
        guard let m = chat.messages.first(where: { $0.id == id }) else { return }
        let had = m.reactions.first(where: \.mine)?.emoji
        chat = chat.reacting(id, emoji)
        // the same emoji again takes it back
        let sent: String? = emoji == had ? nil : emoji
        Task { _ = await model.fetch { try await $0.react(id, sent) } }
    }
}

// MARK: lines

/// a time stamp, a bubble (or a shared title, or photos) or "Read"
private struct ChatLine: View {
    let line: Conversation.Line
    var react: (Int, String?) -> Void

    var body: some View {
        switch line {
        case .stamp(let s):
            Text(s).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkMuted).numbers()
                .frame(maxWidth: .infinity)
                .padding(.top, 8).padding(.bottom, 8)
        case .bubble(let m, let tail):
            ChatBubble(message: m, tail: tail, react: react)
                .padding(.bottom, tail ? 12 : 3)
        case .read:
            Text("Read").font(.system(size: 11)).foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 20)
                .padding(.top, -6).padding(.bottom, 10)
        }
    }
}

/// One message: text in a bubble, photos, or a shared title's card. Long press to react.
struct ChatBubble: View {
    let message: Message
    let tail: Bool
    var react: (Int, String?) -> Void

    private var mine: Bool { message.mine }
    private var reactions: String { message.reactions.map(\.emoji).joined() }

    var body: some View {
        content
            .overlay(alignment: mine ? .topLeading : .topTrailing) { reaction }
            .padding(.top, message.reactions.isEmpty ? 0 : 14)
            .contextMenu { if !message.deleted { menu } }
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
            .padding(.horizontal, 16)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: !mine && tail ? 6 : 20,
                               bottomTrailingRadius: mine && tail ? 6 : 20, topTrailingRadius: 20, style: .continuous)
    }

    @ViewBuilder private var content: some View {
        if message.deleted {
            Text("Message deleted").font(.system(size: 15)).italic().foregroundStyle(Theme.inkMuted)
                .padding(.vertical, 9).padding(.horizontal, 14)
                .overlay(shape.strokeBorder(Theme.keyline, lineWidth: 1))
        } else {
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                if let c = message.card {
                    ChatTitleCard(title: c.card, line: c.line, shape: shape)
                }
                ForEach(Array(message.photos.enumerated()), id: \.offset) { _, p in
                    ChatPhoto(photo: p, shape: shape)
                }
                if !message.body.isEmpty {
                    Text(message.body)
                        .font(.system(size: 16))
                        .foregroundStyle(mine ? Color.white : Theme.ink)
                        .padding(.vertical, 9).padding(.horizontal, 14)
                        .background(mine ? Theme.brand : Theme.fillStrong.opacity(0.66), in: shape)
                        .frame(maxWidth: 270, alignment: mine ? .trailing : .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder private var reaction: some View {
        if !reactions.isEmpty {
            Text(reactions).font(.system(size: 14))
                .padding(.horizontal, 7).frame(height: 26)
                .background(Theme.raised, in: Capsule())
                .overlay(Capsule().stroke(Theme.sheet, lineWidth: 2))
                .offset(x: mine ? -12 : 12, y: -16)
                .accessibilityLabel("Reaction \(reactions)")
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
        if message.reactions.contains(where: \.mine) {
            Button { react(message.id, nil) } label: { Label("Remove reaction", systemImage: "xmark") }
        }
        if !message.body.isEmpty {
            Button { UIPasteboard.general.string = message.body } label: { Label("Copy", systemImage: "doc.on.doc") }
        }
    }
}

/// a photo in a message, at its own shape, at most 240 wide
private struct ChatPhoto: View {
    let photo: Photo
    let shape: UnevenRoundedRectangle

    var body: some View {
        let w: CGFloat = 240
        let h = photo.width > 0 ? min(320, w * CGFloat(photo.height) / CGFloat(photo.width)) : w
        Artwork(url: photo.thumb)
            .frame(width: w, height: h)
            .clipShape(shape)
            .accessibilityLabel("Photo")
    }
}

/// a shared title in the chat: banner, poster over its edge, name, "Anime · TV · 2023", your status
struct ChatTitleCard: View {
    let title: Title
    let line: String
    let shape: UnevenRoundedRectangle

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Artwork(url: title.banner ?? title.cover).frame(height: 104)
            HStack(alignment: .top, spacing: 12) {
                Poster(url: title.cover, width: 58, radius: 7).padding(.top, -36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(2)
                    Text(line).font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
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

    /// "Anime · TV · 2023"
    private func line(_ t: Title) -> String {
        ([t.media.singular] + (t.format.map { [$0] } ?? []) + (t.year.map { [String($0)] } ?? []))
            .joined(separator: " · ")
    }

    private func row(_ e: LibraryEntry) -> some View {
        HStack(spacing: 12) {
            Poster(url: e.title.cover, width: 40, radius: 5, flat: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(line(e.title)).font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
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

/// Someone who isn't a friend wants to message you (GET conversations/:username, box "request"): who they are, what
/// they sent, then Accept / Ignore / Block. Accept turns this page into the conversation.
struct MessageRequestView: View {
    let id: String

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var request: Load<Conversation> = .loading
    @State private var blocking = false

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
        .confirmationDialog("Block \(id)?", isPresented: $blocking, titleVisibility: .visible) {
            Button("Block", role: .destructive) { finish(block: true) }
        } message: {
            Text("They won't be able to message you or see your lists. They aren't told.")
        }
        .task(id: id) { if request.value == nil { await load() } }
    }

    private func content(_ r: Conversation) -> some View {
        VStack(spacing: 0) {
            Avatar(url: r.person.avatar, size: 92)
            Text(r.person.username).font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.ink).padding(.top, 12)
            if r.person.name != r.person.username, !r.person.name.isEmpty {
                Text(r.person.name).font(.system(size: 14)).foregroundStyle(Theme.inkMuted).padding(.top, 3)
            }
            Button("View profile") { model.open(.user(id)) }
                .buttonStyle(.capsule(.tone, .small))
                .padding(.top, 12)
            VStack(spacing: 0) {
                ForEach(Conversation.lines(r.messages, seen: nil)) { line in
                    switch line {
                    case .stamp(let s):
                        Text(s).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkMuted).numbers()
                            .padding(.top, 20).padding(.bottom, 8)
                    case .bubble(let m, let tail):
                        ChatBubble(message: m, tail: tail) { _, _ in }
                            .padding(.bottom, tail ? 12 : 3)
                    case .read:
                        EmptyView()
                    }
                }
            }
            .padding(.top, 8)
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
                Button("Ignore") { finish(block: false) }
                    .buttonStyle(.capsule(.tone, .large, full: true))
                Button("Block") { blocking = true }
                    .buttonStyle(.capsule(.tone, .large, color: Theme.danger, full: true))
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(Theme.sheet)
        .overlay(alignment: .top) { Hairline() }
    }

    private func load() async {
        request = await model.fetch { try await $0.conversation(id) }
    }

    private func accept() {
        let name = id
        SocialSession.answered.insert(name)
        Task { _ = await model.fetch { try await $0.answerMessageRequest(name, accept: true) } }
        var p = model.path(model.tab)
        if !p.isEmpty { p.removeLast() }
        p.append(.conversation(name))
        model.setPath(model.tab, p)
    }

    private func finish(block: Bool) {
        let name = id
        SocialSession.answered.insert(name)
        Task {
            if block {
                _ = await model.fetch { try await $0.block(name) }
            } else {
                _ = await model.fetch { try await $0.answerMessageRequest(name, accept: false) }
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
    @State private var page: Load<FriendsState> = .loading
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                if let p = page.value {
                    list(p.friends.filter { query.isEmpty || $0.username.localizedCaseInsensitiveContains(query)
                        || $0.name.localizedCaseInsensitiveContains(query) })
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

    @ViewBuilder private func list(_ friends: [Person]) -> some View {
        if friends.isEmpty {
            Text(query.isEmpty ? "Add friends to message them." : "No friend called \(query).")
                .font(.system(size: 15)).foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity).padding(.vertical, 40)
        }
        LazyVStack(spacing: 0) {
            ForEach(Array(friends.enumerated()), id: \.element.id) { i, f in
                Button { open(f.username) } label: {
                    SocialPersonRow(user: f.user, line: FriendsState.line(f), separator: i < friends.count - 1) {
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
        page = await model.fetch { try await $0.friends() }
    }
}
