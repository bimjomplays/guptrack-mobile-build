import SwiftUI

/// The Library tab (32): the five media lists with their counts, then your custom lists. Search looks through the
/// whole library; the ⋯ menu has a new list, stats and the offline library.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var searching = false
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    mediaRows
                    listsHeader
                    listsGrid
                } else {
                    results
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
        .pageBackground()
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .modifier(LibraryToolbarSearch(on: $searching, text: $query, prompt: "Search your library"))
        .onChange(of: searching) { _, on in if !on { query = "" } }
        .toolbar { toolbar }
        .refreshable { await model.refresh() }
    }

    // MARK: the five media

    private var mediaRows: some View {
        VStack(spacing: 0) {
            Hairline()
            ForEach(MediaKind.allCases) { m in
                NavigationLink(value: Route.list(m)) {
                    LibraryMediaRow(media: m, line: LibraryLists.mediaLine(model.library, media: m),
                                    count: model.entries(m).count, separator: m != .book)
                }
                .buttonStyle(.plain)
            }
            Hairline()
        }
    }

    // MARK: your lists

    private var listsHeader: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Your lists").font(.section).foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                model.sheet = .newList
            } label: {
                Label("New list", systemImage: "plus")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.brandSoft)
            .labelStyle(TightLabelStyle())
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    @ViewBuilder private var listsGrid: some View {
        let lists = model.customLists
        if lists.isEmpty {
            Text("Make a list to keep titles together, with a note on why each is there.")
                .font(.system(size: 15)).foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, Theme.pad)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                      alignment: .leading, spacing: 16) {
                ForEach(lists) { l in
                    NavigationLink(value: Route.customList(l.id)) {
                        CustomListCard(list: l)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.pad)
        }
    }

    // MARK: search

    @ViewBuilder private var results: some View {
        let found = LibraryLists.search(model.library, query)
        if found.isEmpty {
            ContentUnavailableView.search(text: query).padding(.top, 40)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(found.enumerated()), id: \.element.id) { i, e in
                    LibraryEntryRow(entry: e, separator: i < found.count - 1,
                                    open: { model.open(.title(e.id)) }, plus: { model.step(e.id) })
                        .contextMenu { EntryMenu(entry: e) }
                }
            }
        }
    }

    // MARK: toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                searching = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Search")
            Menu {
                Button {
                    model.sheet = .newList
                } label: {
                    Label("New list", systemImage: "plus")
                }
                Button {
                    model.open(.stats)
                } label: {
                    Label("Stats", systemImage: "chart.bar")
                }
                Button {
                    model.open(.settingsPage(.offline))
                } label: {
                    Label("Offline library", systemImage: "arrow.down.circle")
                }
                Button {
                    model.open(.settingsPage(.importExport))
                } label: {
                    Label("Import & export", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("More")
        }
    }
}

/// Anime · 7 watching · 194 › (32)
private struct LibraryMediaRow: View {
    let media: MediaKind
    let line: String
    let count: Int
    var separator = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: LibraryLists.symbol(media))
                .environment(\.symbolVariants, .none)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color(hex: LibraryLists.colorHex(media)))
                .frame(width: 32)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(media.plural).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(line).font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 8)
                Text(Format.grouped(count)).font(.system(size: 17)).foregroundStyle(Theme.inkMuted).numbers()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(.trailing, Theme.pad)
            .frame(height: 58)
            .overlay(alignment: .bottom) { if separator { Hairline() } }
        }
        .padding(.leading, Theme.pad)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A custom list's card: four covers, the name, "12 titles · 🌐 Public" (32)
private struct CustomListCard: View {
    let list: CustomList

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListCoverStrip(covers: list.covers)
            Text(list.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                .lineLimit(1).padding(.top, 8)
            HStack(spacing: 5) {
                Text("\(list.countLine) ·")
                Image(systemName: list.visibility.symbol).font(.system(size: 11, weight: .semibold))
                Text(list.visibility.label)
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.inkMuted)
            .lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
