import SwiftUI

// The Library tab's shared parts: a title's row (33, 37), its cover (34), the status chips, list mosaics (32, 38),
// the search that opens from a toolbar button, and the custom-list calls with their local edits.

/// One title on a media list (33): cover, title, "ONA · 11 episodes", status and when; the score and progress on
/// the right, and +1 while you're on it. A tap opens the title.
struct LibraryEntryRow: View {
    let entry: LibraryEntry
    var showStatus = true
    var separator = true
    var open: () -> Void
    var plus: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Poster(url: entry.title.cover, width: 48, radius: 6, flat: true)
                .padding(.vertical, 9)
            HStack(spacing: 12) {
                texts
                Spacer(minLength: 0)
                trailing
                if LibraryLists.canStep(entry) {
                    plusButton
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) { if separator { Hairline() } }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.pad)
        .background(Theme.sheet)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityAddTraits(.isButton)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.title.name).font(.rowTitle).foregroundStyle(Theme.ink).lineLimit(1)
            Text(LibraryLists.caption(entry.title)).font(.system(size: 13.5)).foregroundStyle(Theme.inkMuted)
                .numbers().lineLimit(1).padding(.top, 1)
            statusLine.padding(.top, 3)
        }
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            if showStatus {
                StatusDot(status: entry.status, size: 7)
                Text(entry.status.label(entry.media)).foregroundStyle(Theme.inkSoft)
                Text("·")
            }
            Text(LibraryLists.when(entry.updatedAt))
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.inkMuted)
        .lineLimit(1)
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if let s = entry.score10 {
                ScoreLabel(value: s, size: 15)
            }
            if let p = LibraryLists.progressText(entry) {
                Text(p).font(.system(size: 13)).foregroundStyle(Theme.inkMuted).numbers()
            }
        }
        .fixedSize()
    }

    private var plusButton: some View {
        Button(action: plus) {
            Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                .frame(width: 32, height: 32)
                .background(Theme.fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Plus one")
    }
}

/// A title in the covers grid (34): the cover with your score on it, the title under it.
struct LibraryCoverCell: View {
    let entry: LibraryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Artwork(url: entry.title.cover)
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.keyline, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                .overlay(alignment: .bottomTrailing) { badge }
            Text(entry.title.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                .lineLimit(2).multilineTextAlignment(.leading)
                .padding(.top, 7)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var badge: some View {
        if let s = entry.score10 {
            HStack(spacing: 3) {
                Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Theme.star)
                Text(s).font(.system(size: 12, weight: .bold)).foregroundStyle(.white).numbers()
            }
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(.black.opacity(0.6), in: Capsule())
            .padding(6)
        }
    }
}

/// All 194 · Watching 7 · Completed 85…: the status filter over a media list
struct LibraryStatusChips: View {
    let chips: [LibraryStatusChip]
    @Binding var selection: ListStatus?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(chips) { chip in
                    Button {
                        selection = chip.status
                    } label: {
                        ChipLabel(text: chip.label, on: chip.status == selection, count: Format.grouped(chip.count))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chip.status == selection ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.pad)
        }
    }
}

/// A custom list's four covers side by side (the Library's list cards, 32)
struct ListCoverStrip: View {
    let covers: [URL]
    var height: CGFloat = 120

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { i in
                Artwork(url: covers[safe: i])
            }
        }
        .frame(height: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.keyline, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 6)
    }
}

/// A custom list's four covers in a square (a list's page, 38)
struct ListCoverSquare: View {
    let covers: [URL]
    var size: CGFloat = 96

    var body: some View {
        let half = size / 2
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Artwork(url: covers[safe: 0]).frame(width: half, height: half)
                Artwork(url: covers[safe: 1]).frame(width: half, height: half)
            }
            HStack(spacing: 0) {
                Artwork(url: covers[safe: 2]).frame(width: half, height: half)
                Artwork(url: covers[safe: 3]).frame(width: half, height: half)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.keyline, lineWidth: 1))
    }
}

/// The system search, shown once the toolbar's search button is tapped (the mockups keep it in the toolbar)
struct LibraryToolbarSearch: ViewModifier {
    @Binding var on: Bool
    @Binding var text: String
    var prompt: String

    func body(content: Content) -> some View {
        if on {
            content
                .searchable(text: $text, isPresented: $on, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: Text(prompt))
        } else {
            content
        }
    }
}

/// Creating, saving and deleting custom lists: the app API call, then this iPhone's copy (CustomListEdits) so every
/// Library page shows the change at once.
@MainActor
enum CustomListActions {
    static func create(_ draft: CustomListDraft, model: AppModel) async -> CustomList? {
        let r = await model.fetch { try await $0.createList(draft.body) }
        guard let reply = r.value, reply.ok else {
            model.notice = "Couldn't make the list. \(r.error ?? "")"
            return nil
        }
        let edits = CustomListEdits.shared(for: model)
        let list = draft.created(id: reply.id ?? edits.newId(for: draft.trimmedName, taken: []))
        edits.didCreate(list)
        return list
    }

    static func save(_ draft: CustomListDraft, to list: CustomList, model: AppModel) async -> Bool {
        let r = await model.fetch { try await $0.updateList(list.id, draft.body) }
        guard r.value?.ok == true else {
            model.notice = "Couldn't save the list. \(r.error ?? "")"
            return false
        }
        CustomListEdits.shared(for: model).didSave(draft.applied(to: list))
        return true
    }

    /// deletes it and takes its page off the stack
    static func delete(_ list: CustomList, model: AppModel) async -> Bool {
        let r = await model.fetch { try await $0.deleteList(list.id) }
        guard r.value?.ok == true else {
            model.notice = "Couldn't delete the list. \(r.error ?? "")"
            return false
        }
        CustomListEdits.shared(for: model).didDelete(list.id)
        for tab in AppTab.allCases where model.path(tab).contains(.customList(list.id)) {
            model.setPath(tab, model.path(tab).filter { $0 != .customList(list.id) })
        }
        return true
    }
}
