import SwiftUI

/// A custom list (38): its covers, name, description and "Public · 12 titles · updated yesterday"; Edit list, Add
/// titles and Shuffle; then the titles in order with your status, score and the note on why each is there.
/// Your lists come with the library feed, so the page shows offline; one saved or made here shows at once.
struct CustomListView: View {
    let id: String

    @Environment(AppModel.self) private var model

    var body: some View {
        if model.listEdits.isDeleted(id) {
            ContentUnavailableView("This list was deleted", systemImage: "trash").pageBackground()
        } else if let local = model.customList(id) {
            CustomListPage(list: local)
        } else {
            // not in the phone's copy yet (a link, or before the first sync): GET lists, then lists/:slug
            PageLoader(id: id, load: { try await $0.myList(id: Int(id) ?? 0).customList() }) { list in
                CustomListPage(list: list)
            }
            .pageBackground()
        }
    }
}

private struct CustomListPage: View {
    let list: CustomList

    @Environment(AppModel.self) private var model
    @State private var adding = false
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                buttons.padding(.top, 18).padding(.bottom, 10)
                if list.items.isEmpty {
                    ContentUnavailableView {
                        Label("No titles yet", systemImage: "list.bullet")
                    } description: {
                        Text("Add titles from your library, with a note on why each is here.")
                    }
                    .padding(.top, 30)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(list.items.enumerated()), id: \.element.id) { i, item in
                            CustomListRow(rank: i + 1, item: item, entry: model.entry(item.id),
                                          separator: i < list.items.count - 1)
                                .onTapGesture { model.open(.title(item.id)) }
                                .contextMenu { if let e = model.entry(item.id) { EntryMenu(entry: e) } }
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .pageBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $adding) { AddTitlesSheet(list: list) }
        .confirmationDialog("Delete “\(list.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete list", role: .destructive) {
                Task { _ = await CustomListActions.delete(list, model: model) }
            }
        } message: {
            Text("The list goes for good. The titles stay in your library.")
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            ListCoverSquare(covers: list.covers, size: 96)
            VStack(alignment: .leading, spacing: 3) {
                Text(list.name).font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.ink)
                    .lineLimit(2).accessibilityAddTraits(.isHeader)
                if let d = list.description, !d.isEmpty {
                    Text(d).font(.system(size: 14)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                }
                HStack(spacing: 5) {
                    Image(systemName: list.visibility.symbol).font(.system(size: 11, weight: .semibold))
                    Text(list.metaLine())
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.pad)
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button {
                model.sheet = .editList(list.id)
            } label: {
                Label("Edit list", systemImage: "pencil")
            }
            Button {
                adding = true
            } label: {
                Label("Add titles", systemImage: "plus")
            }
            Spacer(minLength: 0)
            Button(action: shuffle) {
                Label("Shuffle", systemImage: "shuffle")
            }
            .disabled(list.items.isEmpty)
        }
        .buttonStyle(.capsule(.tone, .small))
        .padding(.horizontal, Theme.pad)
    }

    /// opens one of the list's titles at random
    private func shuffle() {
        if let item = list.items.randomElement() { model.open(.title(item.id)) }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            ShareLink(item: Route.customList(list.id).url, subject: Text(list.name)) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share")
            Menu {
                Button {
                    model.sheet = .editList(list.id)
                } label: {
                    Label("Edit list", systemImage: "pencil")
                }
                Button {
                    adding = true
                } label: {
                    Label("Add titles", systemImage: "plus")
                }
                Button(action: shuffle) {
                    Label("Shuffle", systemImage: "shuffle")
                }
                Divider()
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete list…", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("More")
        }
    }
}

/// 1 · cover · title · "● Completed · TV" · “note” · score (38)
private struct CustomListRow: View {
    let rank: Int
    let item: CustomListItem
    let entry: LibraryEntry?
    var separator = true

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(rank)").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.inkMuted).numbers()
                .frame(width: 18, alignment: .trailing)
                .frame(maxHeight: .infinity)
            Poster(url: item.title.cover, width: 48, radius: 6, flat: true)
                .padding(.vertical, 9)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title.name).font(.rowTitle).foregroundStyle(Theme.ink).lineLimit(1)
                    HStack(spacing: 6) {
                        if let e = entry {
                            StatusDot(status: e.status, size: 7)
                            Text("\(e.status.label(e.media)) · \(LibraryLists.formatLabel(item.title))")
                        } else {
                            Text(LibraryLists.caption(item.title))
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(1)
                    .padding(.top, 2)
                    if let note = item.note, !note.isEmpty {
                        Text("“\(note)”").font(.system(size: 13)).italic().foregroundStyle(Theme.inkSoft)
                            .lineLimit(1).padding(.top, 3)
                    }
                }
                Spacer(minLength: 0)
                if let s = entry?.score10 {
                    ScoreLabel(value: s, size: 15)
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) { if separator { Hairline() } }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.pad)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Add titles: your library, searchable; tick titles to put them on the list (38's "Add titles")
private struct AddTitlesSheet: View {
    let list: CustomList

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomListDraft
    @State private var query = ""
    @State private var saving = false

    init(list: CustomList) {
        self.list = list
        _draft = State(initialValue: CustomListDraft(list))
    }

    private var found: [LibraryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let all = q.isEmpty ? LibrarySort.title.sorted(model.library) : LibraryLists.search(model.library, q)
        return Array(all.prefix(200))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(found) { e in
                    let on = draft.items.contains { $0.id == e.id }
                    Button {
                        if on { draft.items.removeAll { $0.id == e.id } } else { draft.add(e.title) }
                    } label: {
                        HStack(spacing: 12) {
                            Poster(url: e.title.cover, width: 36, radius: 5, flat: true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.title.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Text("\(e.media.singular) · \(LibraryLists.formatLabel(e.title))")
                                    .font(.system(size: 13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(on ? Theme.brand : Theme.inkFaint)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.sheet)
                    .listRowSeparatorTint(Theme.sep)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.sheet)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your library")
            .navigationTitle("Add titles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        Task {
                            saving = true
                            if await CustomListActions.save(draft, to: list, model: model) { dismiss() }
                            saving = false
                        }
                    }
                    .disabled(saving || draft.items == list.items)
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Editing a list (39): name, description, who can see it; the titles with their notes, dragged to reorder or
/// taken off; and deleting the list.
struct EditListSheet: View {
    let id: String

    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let local = model.customList(id) {
                    EditListForm(list: local)
                } else {
                    PageLoader(id: id, load: { try await $0.myList(id: Int(id) ?? 0).customList() }) { list in
                        EditListForm(list: list)
                    }
                }
            }
            .background(Theme.sheet)
            .navigationTitle("Edit list")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }
}

private struct EditListForm: View {
    let list: CustomList

    @Environment(AppModel.self) private var model
    @State private var draft: CustomListDraft
    @State private var noteFor: CustomListItem?
    @State private var noteText = ""
    @State private var confirmDelete = false
    @State private var saving = false

    init(list: CustomList) {
        self.list = list
        _draft = State(initialValue: CustomListDraft(list))
    }

    var body: some View {
        List {
            fields
                .listRowInsets(EdgeInsets(top: 0, leading: Theme.pad, bottom: 0, trailing: Theme.pad))
                .listRowSeparator(.hidden)
                .listRowBackground(Theme.sheet)
            Section {
                ForEach(draft.items) { item in
                    EditListRow(item: item) {
                        noteText = item.note ?? ""
                        noteFor = item
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 12))
                    .listRowBackground(Theme.sheet)
                    .listRowSeparatorTint(Theme.sep)
                }
                .onDelete { draft.remove(at: $0) }
                .onMove { draft.move(from: $0, to: $1) }
            } header: {
                Text(draft.reorderLine)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .textCase(nil)
                    .padding(.top, 14)
            }
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete list…", systemImage: "trash")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.danger)
            }
            .buttonStyle(.borderless)
            .listRowInsets(EdgeInsets(top: 22, leading: Theme.pad, bottom: 22, trailing: Theme.pad))
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.sheet)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) { model.sheet = nil }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm) { save() }
                    .disabled(!draft.isValid || saving)
            }
        }
        .alert("Note", isPresented: Binding(get: { noteFor != nil }, set: { if !$0 { noteFor = nil } }),
               presenting: noteFor) { item in
            TextField("Why it's here", text: $noteText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { draft.setNote(noteText, for: item.id) }
        } message: { item in
            Text(item.title.name)
        }
        .confirmationDialog("Delete “\(list.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete list", role: .destructive) {
                Task {
                    if await CustomListActions.delete(list, model: model) { model.sheet = nil }
                }
            }
        } message: {
            Text("The list goes for good. The titles stay in your library.")
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Name").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                .padding(.bottom, 6)
            TextField("Name", text: $draft.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) { Hairline() }
            Text("Description").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                .padding(.top, 14).padding(.bottom, 6)
            TextField("What ties these together", text: $draft.description, axis: .vertical)
                .font(.system(size: 16))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1...4)
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) { Hairline() }
            Picker(selection: $draft.visibility) {
                ForEach(Visibility.allCases) { v in
                    Label(v.label, systemImage: v.symbol).tag(v)
                }
            } label: {
                Text("Who can see it").font(.system(size: 16)).foregroundStyle(Theme.ink)
            }
            .pickerStyle(.menu)
            .tint(Theme.inkMuted)
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) { Hairline() }
        }
        .padding(.top, 8)
    }

    private func save() {
        saving = true
        Task {
            if await CustomListActions.save(draft, to: list, model: model) { model.sheet = nil }
            saving = false
        }
    }
}

/// a title while editing: cover, name, its note (or "Add a note"); the system adds take-off and the grip (39)
private struct EditListRow: View {
    let item: CustomListItem
    var editNote: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Poster(url: item.title.cover, width: 40, radius: 5, flat: true)
                .padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Button(action: editNote) {
                    if let n = item.note, !n.isEmpty {
                        Text("“\(n)”").foregroundStyle(Theme.inkSoft)
                    } else {
                        Text("Add a note").foregroundStyle(Theme.brandSoft)
                    }
                }
                .font(.system(size: 13))
                .lineLimit(1)
                .buttonStyle(.borderless)
            }
            Spacer(minLength: 0)
        }
    }
}
