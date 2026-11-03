import SwiftUI

/// Notifications (08), pushed from Home's bell: Today, This week and Earlier as plain hairline rows. Friend requests
/// are answered inline; a tap opens the person, the conversation, the activity, the review or the title. Opening the
/// bell marks everything seen (POST notices/seen) and clears Home's dot; the rows keep their dots for this visit
/// until Mark all read in the toolbar.
struct NotificationsView: View {
    @Environment(AppModel.self) private var model
    @State private var items: [BellNotice]?
    @State private var failed: String?
    /// friend requests answered here: username -> accepted
    @State private var answered: [String: Bool] = [:]

    var body: some View {
        content
            .pageBackground()
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        markAllRead()
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .accessibilityLabel("Mark all read")
                    .disabled(NoticeSection.unseen(items ?? []) == 0)
                }
            }
            .task { if items == nil { await load() } }
            .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let items {
            if items.isEmpty {
                ContentUnavailableView("No notifications", systemImage: "bell",
                                       description: Text("Friend requests, comments and new episodes show up here."))
            } else {
                list(items)
            }
        } else if let failed {
            ContentUnavailableView {
                Label("Couldn't load this", systemImage: "wifi.exclamationmark")
            } description: {
                Text(failed)
            } actions: {
                Button("Try again") { Task { await load() } }.buttonStyle(.capsule(.tone, .small))
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func list(_ items: [BellNotice]) -> some View {
        let sections = NoticeSection.of(items)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { si, section in
                    Text(section.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, Theme.pad)
                        .padding(.top, si == 0 ? 0 : 22)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { i, item in
                        NotificationRow(item: item, entry: item.ref.flatMap { model.entry($0.titleId) },
                                        separator: i < section.items.count - 1 || si < sections.count - 1,
                                        answer: answerBinding(item))
                    }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
    }

    private func answerBinding(_ item: BellNotice) -> FriendAnswer? {
        guard item.kind == .friendRequest, let u = item.user else { return nil }
        return FriendAnswer(state: answered[u]) { accept in
            answered[u] = accept
            markRead(item.id)
            Task { _ = await model.fetch { try await $0.answerFriend(u, accept: accept) } }
        }
    }

    private func load() async {
        switch await model.fetch({ try await $0.notices() }) {
        case .loaded(let list):
            items = list
            failed = nil
            model.unreadNotifications = 0
            if NoticeSection.unseen(list) > 0 {
                _ = await model.fetch { try await $0.markNoticesSeen() }
            }
        case .failed(let why):
            if items == nil { failed = why }
        case .loading:
            break
        }
    }

    private func markRead(_ id: String) {
        guard let i = items?.firstIndex(where: { $0.id == id }) else { return }
        items?[i].unseen = false
    }

    private func markAllRead() {
        guard var all = items else { return }
        for i in all.indices { all[i].unseen = false }
        items = all
        model.unreadNotifications = 0
        Task { _ = await model.fetch { try await $0.markNoticesSeen() } }
    }
}

/// a friend request's inline answer: nil until answered, then accepted (true) or declined
fileprivate struct FriendAnswer {
    var state: Bool?
    var answer: (Bool) -> Void
}

/// One notification: the unread dot, an avatar or a poster, the sentence with names in bold, the grey time line,
/// Accept / Decline on friend requests. The notice carries one picture (`cover`): the person's avatar when a person
/// leads, else the title's poster.
private struct NotificationRow: View {
    let item: BellNotice
    let entry: LibraryEntry?
    var separator = true
    var answer: FriendAnswer?

    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            lead.padding(.vertical, 12)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(sentence)
                        .font(.system(size: 15))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.caption(entry: entry))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkMuted)
                        .numbers()
                        .padding(.top, 2)
                    if let answer { answerButtons(answer) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { if separator { Hairline() } }
        }
        .padding(.horizontal, Theme.pad)
        .overlay(alignment: .leading) {
            if item.unseen {
                Circle().fill(Theme.brand).frame(width: 8, height: 8).padding(.leading, 7)
                    .accessibilityLabel("Unread")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .accessibilityElement(children: answer == nil ? .combine : .contain)
        .accessibilityAction(named: "Open") { open() }
    }

    @ViewBuilder
    private var lead: some View {
        if item.leadsWithPerson {
            Avatar(url: item.cover, size: 40)
        } else {
            Poster(url: item.cover, width: 40, radius: 6, flat: true)
        }
    }

    /// names and titles semibold in full ink, the rest soft
    private var sentence: AttributedString {
        var out = AttributedString()
        for run in item.runs {
            var piece = AttributedString(run.text)
            let color: Color = run.strong ? Theme.ink : Theme.inkSoft
            piece.foregroundColor = color
            if run.strong { piece.font = Font.system(size: 15, weight: .semibold) }
            out += piece
        }
        return out
    }

    @ViewBuilder
    private func answerButtons(_ a: FriendAnswer) -> some View {
        if let accepted = a.state {
            Text(accepted ? "You're now friends" : "Request declined")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accepted ? Theme.color(.current) : Theme.inkMuted)
                .padding(.top, 10)
        } else {
            HStack(spacing: 8) {
                Button("Accept") { a.answer(true) }
                    .buttonStyle(.capsule(.tint, .small))
                Button("Decline") { a.answer(false) }
                    .buttonStyle(.capsule(.tone, .small))
            }
            .padding(.top, 10)
        }
    }

    private func open() {
        if let r = item.route(me: model.account?.user.username) { model.open(r) }
    }
}
