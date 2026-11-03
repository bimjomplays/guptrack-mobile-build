import SwiftUI

/// Send a title to friends (53): the title on top, friends to pick (ringed and ticked when chosen), Search for the
/// rest, a short message; "Send 2" in the bar. The people are GET messages/recipients (recent conversations first,
/// then friends); Send posts the title as a card to each (POST conversations/:username/messages).
struct SendToSheet: View {
    let titleId: String

    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            SheetTitleLoader(titleId: titleId) { title, _ in
                PageLoader(id: titleId, load: { try await $0.recipients() }) { page in
                    SendForm(title: title, friends: page.recipients)
                }
            }
            .navigationTitle("Send to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { model.sheet = nil }
                        .accessibilityLabel("Cancel")
                }
            }
        }
        .presentationDetents([.height(520), .large])
        .presentationDragIndicator(.visible)
    }
}

private struct SendForm: View {
    let title: Title
    let friends: [TitleSheets.Recipient]

    @Environment(AppModel.self) private var model
    @State private var picks = TitleSheets.SendPicks()
    @State private var searching = false
    @State private var sending = false
    @FocusState private var searchFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleRow
                Text("Friends").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .padding(.top, 16).padding(.bottom, 12)
                if searching { searchField.padding(.bottom, 14) }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(picks.shown(friends)) { f in
                        cell(f)
                    }
                    if !searching { searchCell }
                }
                messageField.padding(.top, 22)
            }
            .padding(.horizontal, Theme.pad)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm) {
                    send()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane")
                        Text("Send")
                        if !picks.picked.isEmpty {
                            Text("\(picks.picked.count)").monospacedDigit().opacity(0.8)
                        }
                    }
                }
                .disabled(!picks.canSend || sending)
                .accessibilityLabel(picks.sendLabel)
            }
        }
    }

    private var titleRow: some View {
        HStack(spacing: 12) {
            Poster(url: title.cover, width: 44, radius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(title.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(TitleSheets.summary(title)).font(.system(size: 13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .combine)
    }

    private func cell(_ f: TitleSheets.Recipient) -> some View {
        let on = picks.isOn(f.username)
        return Button {
            picks.toggle(f.username)
        } label: {
            VStack(spacing: 7) {
                PickedAvatar(url: f.avatarURL, on: on)
                Text(f.username).font(.system(size: 13, weight: on ? .semibold : .medium))
                    .foregroundStyle(on ? Theme.ink : Theme.inkSoft)
                    .lineLimit(1)
            }
            .frame(width: 78)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!f.canSend)
        .opacity(f.canSend ? 1 : 0.4)
        .accessibilityLabel(f.username)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var searchCell: some View {
        Button {
            searching = true
            searchFocused = true
        } label: {
            VStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 64, height: 64)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                Text("Search").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
            }
            .frame(width: 78)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search friends")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkMuted)
            TextField("Search friends", text: $picks.query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button {
                picks.query = ""
                searching = false
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop searching")
        }
        .font(.system(size: 17))
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Theme.fill, in: Capsule())
    }

    private var messageField: some View {
        TextField("Add a message", text: $picks.message)
            .font(.system(size: 17))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Theme.fill, in: Capsule())
            .accessibilityLabel("Add a message")
    }

    private func send() {
        guard let body = picks.body(title.id) else { return }
        let to = picks.to(friends)
        sending = true
        Task {
            var failed: [String] = []
            var why: String?
            for username in to {
                let r: Load<Void> = await model.fetch { try await $0.sendMessage(to: username, body) }
                if let e = r.error {
                    failed.append(username)
                    why = e
                }
            }
            sending = false
            if let why {
                // keep only those it didn't reach picked, so Send tries just them again
                picks.picked = picks.picked.filter { failed.contains($0) }
                model.notice = "Couldn't send it to \(failed.joined(separator: ", ")): \(why)"
                return
            }
            model.sheet = nil
        }
    }
}

/// A friend's 64pt picture; picked: a brand ring with a gap and a tick on the corner (the kit's Avatar ring is the
/// status green and has no tick, so this draws its own).
private struct PickedAvatar: View {
    let url: URL?
    let on: Bool

    var body: some View {
        Avatar(url: url, size: 64)
            .overlay {
                if on {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Theme.brand, lineWidth: 2.5)
                        .padding(-5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if on {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Theme.brand, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.panel, lineWidth: 2.5).padding(-2.5))
                        .offset(x: 5, y: 5)
                }
            }
            .padding(5)
    }
}
