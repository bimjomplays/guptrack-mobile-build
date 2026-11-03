import SwiftUI

// The Social tab's shared pieces (44-54): the Activity · Friends · Messages switch, a feed row, likes and replies,
// the title card of a thread, a reply, a person row, the composer at the foot of threads and chats.

extension Theme {
    /// the heart of a like (iOS's pink)
    static let socialLike = Color(hex: 0xFF375F)
}

extension AppModel {
    /// you, as likes, replies and messages show you
    var socialMe: Person {
        let u = account?.user ?? UserRef(username: "you", name: "You", avatar: nil)
        return Person(username: u.username, name: u.name, avatar: u.avatar, relation: .me)
    }
}

// MARK: the switch under the large title

enum SocialSegment: String, CaseIterable, Identifiable {
    case activity, friends, messages

    var id: String { rawValue }

    var label: String {
        switch self {
        case .activity: return "Activity"
        case .friends: return "Friends"
        case .messages: return "Messages"
        }
    }
}

/// Activity · Friends · Messages (the unread count on Messages), as the mockup's segmented control
struct SocialSwitch: View {
    @Binding var selection: SocialSegment
    let unread: Int
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SocialSegment.allCases) { s in
                segment(s)
            }
        }
        .padding(2)
        .frame(height: 34)
        .background(Theme.fill, in: Capsule())
    }

    private func segment(_ s: SocialSegment) -> some View {
        let on = s == selection
        return Button {
            withAnimation(.snappy(duration: 0.25)) { selection = s }
        } label: {
            HStack(spacing: 5) {
                Text(s.label)
                if s == .messages && unread > 0 {
                    Text("\(unread)")
                        .font(.system(size: 11, weight: .bold)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Theme.danger, in: Capsule())
                }
            }
            .font(.system(size: 14, weight: on ? .semibold : .medium))
            .foregroundStyle(on ? Color.white : Theme.inkSoft)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if on {
                    Capsule().fill(Color.white.opacity(0.2))
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
                        .matchedGeometryEffect(id: "on", in: ns)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.label)
        .accessibilityValue(Text(s == .messages && unread > 0 ? String(unread) + " unread" : String()))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: loading inside a scrolling page

/// a spinner while a section loads, a plain message with Try again when it doesn't
struct SocialLoading: View {
    var error: String?
    var retry: () -> Void

    var body: some View {
        if let error {
            ContentUnavailableView {
                Label("Couldn't load this", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try again", action: retry).buttonStyle(.capsule(.tone, .small))
            }
            .padding(.top, 40)
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
        }
    }
}

// MARK: likes and replies

/// ♥ 4   💬 2 under an item; the heart likes it
struct SocialCounts: View {
    let likes: Int
    let replies: Int
    let liked: Bool
    /// someone else's: yours can't be liked, so the heart only counts
    var canLike = true
    var like: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            Button(action: like) {
                HStack(spacing: 6) {
                    Image(systemName: liked ? "heart.fill" : "heart").font(.system(size: 16, weight: .medium))
                    if likes > 0 { Text("\(likes)") }
                }
                .foregroundStyle(liked ? Theme.socialLike : Theme.inkMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canLike)
            .accessibilityLabel(canLike ? (liked ? "Unlike" : "Like") : "Likes")
            .accessibilityValue("\(likes)")
            HStack(spacing: 6) {
                Image(systemName: "bubble.left").font(.system(size: 16, weight: .medium))
                if replies > 0 { Text("\(replies)") }
            }
            .foregroundStyle(Theme.inkMuted)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(replies) replies")
        }
        .font(.system(size: 14))
        .numbers()
    }
}

/// [avatars] Liked by tobiwan and 3 others ............ ♥ 4 (no heart button on your own: canLike is false)
struct SocialLikedBy: View {
    let reactions: Reactions
    var like: () -> Void

    private var likes: Int { reactions.likes }
    private var liked: Bool { reactions.liked }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: -7) {
                ForEach(reactions.likers.prefix(3)) { u in
                    Avatar(url: u.avatar, size: 24)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.sheet, lineWidth: 2))
                }
            }
            line.font(.system(size: 14)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            Spacer(minLength: 8)
            if reactions.canLike {
                Button(action: like) {
                    HStack(spacing: 6) {
                        Image(systemName: liked ? "heart.fill" : "heart").font(.system(size: 18, weight: .medium))
                        Text("\(likes)").numbers()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(liked ? Theme.socialLike : Theme.inkMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(liked ? "Unlike" : "Like")
                .accessibilityValue("\(likes)")
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "heart").font(.system(size: 18, weight: .medium))
                    Text("\(likes)").numbers()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkMuted)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(likes) likes")
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var line: Text {
        guard let l = reactions.likedBy else { return Text("No likes yet") }
        let name = Text(l.name).fontWeight(.semibold).foregroundStyle(Theme.ink)
        return l.rest.isEmpty ? Text("Liked by \(name)") : Text("Liked by \(name) \(l.rest)")
    }
}

/// one reply: avatar, name and time, the text, Reply (replies carry no likes in the contract, so no heart)
struct SocialReplyRow: View {
    let reply: Reply
    var separator = true
    var answer: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { model.open(.user(reply.author.username)) } label: {
                Avatar(url: reply.author.avatar, size: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(reply.author.username)
            .padding(.top, 12)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(reply.author.username).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text(Format.ago(reply.date)).font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
                    }
                    Text(reply.body).font(.system(size: 15)).foregroundStyle(Theme.inkSoft)
                        .lineSpacing(2).padding(.top, 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Reply", action: answer)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                        .buttonStyle(.plain)
                        .padding(.top, 7)
                        .accessibilityLabel("Reply to \(reply.author.username)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { if separator { Hairline() } }
        }
        .padding(.horizontal, Theme.pad)
    }
}

// MARK: the title in a thread

/// The title a thread is about: banner art under a flat dark layer (no gradient), the poster, the title, its line
/// and your own status (or Add when it isn't on your list). Opens the title.
struct SocialTitleCard: View {
    let title: Title

    @Environment(AppModel.self) private var model

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Artwork(url: title.banner ?? title.cover)
            .overlay(Color.black.opacity(0.58))
            .frame(height: 132)
            .overlay(alignment: .leading) { content }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.keyline, lineWidth: 1))
            .contentShape(shape)
            .onTapGesture { model.open(.title(title.id)) }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Open") { model.open(.title(title.id)) }
            .padding(.horizontal, Theme.pad)
    }

    private var content: some View {
        HStack(spacing: 12) {
            Poster(url: title.cover, width: 72, radius: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(title.name).font(.system(size: 16, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                Text(HomeShelves.startLine(title)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1).padding(.top, 2)
                status.padding(.top, 9)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    @ViewBuilder private var status: some View {
        if let e = model.entry(title.id) {
            StatusPill(status: e.status, media: e.media, small: true) { s in
                _ = model.change(e.id, LibraryPatch(status: s))
            }
        } else {
            Button {
                _ = model.change(title.id, LibraryPatch(status: .planned), title: title)
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.capsule(.tone, .small, color: .white))
        }
    }
}

// MARK: people

/// A person in a list: the avatar, the name, a line, something on the right. (The contract has no online status.)
struct SocialPersonRow<Trailing: View>: View {
    let user: UserRef
    let line: String
    var separator = true
    var size: CGFloat = 44
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            Avatar(url: user.avatar, size: size)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(user.username).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(line).font(.system(size: 13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.trailing, Theme.pad)
            .frame(minHeight: 66)
            .overlay(alignment: .bottom) { if separator { Hairline() } }
        }
        .padding(.leading, Theme.pad)
        .contentShape(Rectangle())
    }
}

/// "Requests 2"  ......  Sent 1   Blocked : a small label over a list, with links on the right
struct SocialListHeader<Trailing: View>: View {
    let label: String
    var count: Int?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 4) {
                    Text(label)
                    if let count { Text("\(count)").numbers() }
                }
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                .accessibilityAddTraits(.isHeader)
                Spacer()
                trailing()
            }
            .padding(.horizontal, Theme.pad)
            .padding(.bottom, 6)
            Hairline()
        }
    }
}

// MARK: the composer

/// The bar at the foot of a thread or chat: + (a menu), the text field in a glass capsule, the send arrow.
struct SocialComposer<PlusMenu: View>: View {
    let placeholder: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var send: () -> Void
    @ViewBuilder var menu: () -> PlusMenu

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                menu()
            } label: {
                Image(systemName: "plus").font(.system(size: 19, weight: .medium)).foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .accessibilityLabel("Add")
            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .font(.system(size: 17))
                    .lineLimit(1...5)
                    .focused(focused)
                    .accessibilityLabel(placeholder)
                    .padding(.vertical, 11)
                Image(systemName: "face.smiling").font(.system(size: 20)).foregroundStyle(Theme.inkMuted)
                    .padding(.bottom, 11)
                    .accessibilityHidden(true)
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(canSend ? Theme.brand : Theme.fillStrong, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send")
                .padding(.bottom, 6)
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .frame(minHeight: 44)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}
