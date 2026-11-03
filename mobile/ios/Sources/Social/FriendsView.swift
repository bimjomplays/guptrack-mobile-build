import SwiftUI

/// Friends (46) on its own page: the same list as Social › Friends (GET friends).
struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @State private var page: Load<FriendsState> = .loading

    var body: some View {
        ScrollView {
            Group {
                if let p = page.value {
                    FriendsContent(state: Binding(get: { p }, set: { page = .loaded($0) }))
                } else {
                    SocialLoading(error: page.error) { Task { await load() } }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .pageBackground()
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.sheet = .addFriend
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel("Add friend")
            }
        }
        .task { if page.value == nil { await load() } }
        .refreshable { await load() }
    }

    private func load() async {
        page = await model.fetch { try await $0.friends() }
    }
}

/// Requests (Accept, ✕) then friends (since when, Compare). Sent and Blocked switch the list in place: there's no
/// page of their own for them.
struct FriendsContent: View {
    @Binding var state: FriendsState

    private var page: FriendsState { state }

    enum Shown { case friends, sent, blocked }

    @Environment(AppModel.self) private var model
    @State private var shown: Shown = .friends

    var body: some View {
        LazyVStack(spacing: 0) {
            if !page.incoming.isEmpty {
                SocialListHeader(label: "Requests", count: page.incoming.count) { EmptyView() }
                ForEach(Array(page.incoming.enumerated()), id: \.element.id) { i, r in
                    requestRow(r, separator: i < page.incoming.count - 1)
                }
            }
            SocialListHeader(label: heading, count: count) { links }
                .padding(.top, page.incoming.isEmpty ? 0 : 22)
            switch shown {
            case .friends: friendRows
            case .sent: sentRows
            case .blocked: blockedRows
            }
        }
        .animation(.snappy, value: page)
    }

    private var heading: String {
        switch shown {
        case .friends: return "Friends"
        case .sent: return "Sent requests"
        case .blocked: return "Blocked"
        }
    }

    private var count: Int? {
        switch shown {
        case .friends: return page.friends.count
        case .sent: return page.outgoing.count
        case .blocked: return nil
        }
    }

    private var links: some View {
        HStack(spacing: 16) {
            if shown != .friends {
                Button("Friends") { shown = .friends }
            }
            if shown != .sent {
                Button { shown = .sent } label: {
                    HStack(spacing: 4) {
                        Text("Sent")
                        Text("\(page.outgoing.count)").numbers()
                    }
                }
                .accessibilityLabel("Sent \(page.outgoing.count)")
            }
            if shown != .blocked {
                Button("Blocked") { shown = .blocked }
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.brandSoft)
        .buttonStyle(.plain)
    }

    // MARK: rows

    private func requestRow(_ r: Person, separator: Bool) -> some View {
        SocialPersonRow(user: r.user, line: FriendsState.line(r), separator: separator) {
            HStack(spacing: 6) {
                Button("Accept") { answer(r.id, accept: true) }
                    .buttonStyle(.capsule(.tint, .small))
                    .accessibilityLabel("Accept \(r.id)")
                Button { answer(r.id, accept: false) } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.inkSoft)
                        .frame(width: 32, height: 32)
                        .background(Theme.fill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decline \(r.id)")
            }
        }
        .onTapGesture { model.open(.user(r.id)) }
    }

    @ViewBuilder private var friendRows: some View {
        if page.friends.isEmpty {
            ContentUnavailableView("No friends yet", systemImage: "person.2",
                                   description: Text("Find someone by their username with the button above."))
                .padding(.top, 20)
        }
        ForEach(Array(page.friends.enumerated()), id: \.element.id) { i, f in
            SocialPersonRow(user: f.user, line: FriendsState.line(f), separator: i < page.friends.count - 1) {
                Button { model.open(.compare(f.id)) } label: {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.brandSoft)
                        .frame(width: 34, height: 34)
                        .background(Theme.fill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Compare with \(f.id)")
            }
            .onTapGesture { model.open(.user(f.id)) }
            .contextMenu {
                Button { model.open(.user(f.id)) } label: { Label("View profile", systemImage: "person") }
                Button { model.open(.conversation(f.id)) } label: { Label("Message", systemImage: "bubble.left") }
                Button { model.open(.compare(f.id)) } label: { Label("Compare", systemImage: "arrow.left.arrow.right") }
            }
        }
    }

    @ViewBuilder private var sentRows: some View {
        if page.outgoing.isEmpty {
            empty("No requests waiting")
        }
        ForEach(Array(page.outgoing.enumerated()), id: \.element.id) { i, r in
            SocialPersonRow(user: r.user, line: FriendsState.line(r), separator: i < page.outgoing.count - 1) {
                Button("Cancel") {
                    state = page.cancelling(r.id)
                    send { try await $0.cancelFriendRequest(r.id) }
                }
                .buttonStyle(.capsule(.tone, .small))
                .accessibilityLabel("Cancel request to \(r.id)")
            }
            .onTapGesture { model.open(.user(r.id)) }
        }
    }

    @ViewBuilder private var blockedRows: some View {
        if page.blocked.isEmpty {
            empty("Nobody blocked")
        }
        ForEach(Array(page.blocked.enumerated()), id: \.element) { i, name in
            SocialPersonRow(user: UserRef(username: name, name: name, avatar: nil),
                            line: "Can't message you or see your lists", separator: i < page.blocked.count - 1) {
                Button("Unblock") {
                    state = page.unblocking(name)
                    send { try await $0.unblock(name) }
                }
                .buttonStyle(.capsule(.tone, .small))
                .accessibilityLabel("Unblock \(name)")
            }
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(.system(size: 15)).foregroundStyle(Theme.inkMuted)
            .frame(maxWidth: .infinity).padding(.vertical, 30)
    }

    // MARK: changes

    private func answer(_ username: String, accept: Bool) {
        state = accept ? page.accepting(username) : page.declining(username)
        Task { _ = await model.fetch { try await $0.answerFriend(username, accept: accept) } }
    }

    private func send(_ work: @escaping (APIClient) async throws -> OKReply) {
        Task { _ = await model.fetch(work) }
    }
}

// MARK: Find someone (47)

/// Add a friend by their exact username (GET users/:username/person): one result with Add Friend.
struct AddFriendSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var result: Load<Person?>?
    @State private var answered: [String: Relation] = [:]
    @State private var asked: Set<String> = []
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                field
                Text("Type their whole username, as they sign in with it.")
                    .font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, 4).padding(.top, 8)
                found.padding(.top, 18)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, 8)
            .pageBackground()
            .navigationTitle("Find someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
            .task(id: FriendSearch.query(text)) { await search() }
            .onAppear { focused = true }
        }
        .presentationDetents([.large])
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkMuted)
            TextField("Username", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .font(.system(size: 17))
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Theme.fill, in: Capsule())
    }

    @ViewBuilder private var found: some View {
        let q = FriendSearch.query(text)
        if q.isEmpty {
            EmptyView()
        } else if let r = result {
            if let found = r.value, let f = found {
                row(f)
            } else if let why = r.error {
                Text(why).font(.system(size: 15)).foregroundStyle(Theme.inkMuted)
            } else if r.value != nil {
                Text("Nobody goes by \(q).").font(.system(size: 15)).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    private func row(_ f: Person) -> some View {
        HStack(spacing: 14) {
            Avatar(url: f.avatar, size: 52)
            VStack(alignment: .leading, spacing: 1) {
                Text(f.username).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(FriendSearch.line(f)).font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 8)
            action(f)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Hairline() }
        .overlay(alignment: .bottom) { Hairline() }
    }

    @ViewBuilder private func action(_ f: Person) -> some View {
        let name = f.username
        let relation = answered[name] ?? f.relation
        if relation == .me {
            Text("That's you").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.inkMuted)
        } else if relation == .friend {
            Button("Message") {
                model.sheet = nil
                model.tab = .social
                model.open(.conversation(name))
            }
            .buttonStyle(.capsule(.tone, .small))
        } else if relation == .outgoing || asked.contains(name) {
            Label("Requested", systemImage: "checkmark")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                .labelStyle(TightLabelStyle())
        } else if relation == .incoming {
            Button("Accept") {
                answered[name] = .friend
                Task {
                    let r = await model.fetch { try await $0.answerFriend(name, accept: true) }
                    answered[name] = r.value ?? .incoming
                }
            }
            .buttonStyle(.capsule(.tint, .small))
            .accessibilityLabel("Accept \(name)")
        } else {
            Button {
                asked.insert(name)
                Task {
                    let r = await model.fetch { try await $0.requestFriend(name) }
                    if let now = r.value { answered[name] = now } else { asked.remove(name) }
                }
            } label: {
                Label("Add Friend", systemImage: "person.badge.plus")
            }
            .buttonStyle(.capsule(.tint, .small))
        }
    }

    private func search() async {
        let q = FriendSearch.query(text)
        guard !q.isEmpty else { result = nil; return }
        // a short wait so each key doesn't ask the server
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        result = await model.fetch { try await $0.findPerson(q) }
    }
}
