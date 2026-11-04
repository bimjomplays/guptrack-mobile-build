import SwiftUI

/// Add to a custom list (26): your lists (GET titles/:kind/:id/lists) with a 2×2 cover collage each, ticked when the
/// title is on them, and New list on top. Ticks are kept until Done, which sends one add or take-off per list that
/// changed; ✕ sends nothing. The collage, count and who can see it come from the phone's copy of your lists.
struct AddToListSheet: View {
    let titleId: String

    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            SheetTitleLoader(titleId: titleId) { title, _ in
                PageLoader(id: titleId, load: { try await $0.listChoices(titleId) }) { choices in
                    ListPickForm(title: title, picks: TitleSheets.ListPicks(titleId: titleId, choices: choices))
                }
            }
            .navigationTitle("Add to a list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { model.sheet = nil }
                        .accessibilityLabel("Cancel")
                }
            }
        }
        .presentationDetents([.height(540), .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ListPickForm: View {
    let title: Title
    @State var picks: TitleSheets.ListPicks

    @Environment(AppModel.self) private var model
    @State private var sending = false
    @State private var making = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                newListRow
                ForEach(Array(picks.choices.enumerated()), id: \.element.id) { i, choice in
                    row(choice, last: i == picks.choices.count - 1)
                }
                Text("Lists can mix anime, shows, films, manga and books.")
                    .font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                    .lineSpacing(2)
                    .padding(.top, 14)
            }
            .padding(.horizontal, Theme.pad)
            .padding(.bottom, 24)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", role: .confirm) { done() }
                    .disabled(sending)
            }
        }
        .navigationDestination(isPresented: $making) {
            // POST lists with this title on it; back here, the new list is on top and ticked
            NewListForm(item: title) { list in
                if let id = list.serverId { picks.made(id, name: list.name) }
                making = false
            }
        }
    }

    private var newListRow: some View {
        Button {
            making = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus").font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.brandSoft)
                    .frame(width: 52, height: 52)
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Theme.brand.opacity(0.55), lineWidth: 1.5))
                Text("New list").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.brandSoft)
                Spacer(minLength: 0)
            }
            .frame(height: 68)
            .overlay(alignment: .bottom) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ choice: ListWire.Choice, last: Bool) -> some View {
        let on = picks.isOn(choice.id)
        let list = model.customList(String(choice.id))
        return Button {
            picks.toggle(choice.id)
        } label: {
            HStack(spacing: 14) {
                SheetCoverCollage(urls: list?.covers ?? [])
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if let caption = picks.caption(choice, list: list) {
                        Text(caption).font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 8)
                SheetTick(on: on)
            }
            .frame(height: 72)
            .overlay(alignment: .bottom) { if !last { Hairline() } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func done() {
        let changes = picks.changes
        guard !changes.isEmpty else { model.sheet = nil; return }
        guard let item = ListWire.ListTitle(title) else { model.sheet = nil; return }
        sending = true
        Task {
            var failed: String?
            for c in changes {
                let r: Load<OKReply> = await model.fetch { api in
                    if c.add { return try await api.putOnList(c.listId, item) }
                    return try await api.takeOffList(c.listId, item.ref)
                }
                if let why = r.error { failed = why }
            }
            sending = false
            model.sheet = nil
            if let failed { model.notice = "Couldn't change your lists: \(failed)" }
            await model.syncLibrary()
        }
    }
}

/// a list's first four covers, 2×2
struct SheetCoverCollage: View {
    let urls: [URL]
    var size: CGFloat = 52

    var body: some View {
        let cell = (size - 1.5) / 2
        VStack(spacing: 1.5) {
            HStack(spacing: 1.5) {
                Artwork(url: urls[safe: 0]).frame(width: cell, height: cell)
                Artwork(url: urls[safe: 1]).frame(width: cell, height: cell)
            }
            HStack(spacing: 1.5) {
                Artwork(url: urls[safe: 2]).frame(width: cell, height: cell)
                Artwork(url: urls[safe: 3]).frame(width: cell, height: cell)
            }
        }
        .frame(width: size, height: size)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

/// the round tick on the right of a list row
struct SheetTick: View {
    let on: Bool

    var body: some View {
        ZStack {
            if on {
                Circle().fill(Theme.brand)
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            } else {
                Circle().strokeBorder(Theme.inkFaint, lineWidth: 1.5)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }
}
