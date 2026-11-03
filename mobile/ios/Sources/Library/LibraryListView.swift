import SwiftUI

/// A media list (33-37): the title is a menu that switches media, view and your lists (35); the summary and the
/// status chips; then rows (with +1 and swipe actions, 37) or a grid of covers (34). Sort and the format filter sit
/// in the toolbar (36). The view and sort are remembered per media.
struct LibraryListView: View {
    let media: MediaKind

    @Environment(AppModel.self) private var model
    @AppStorage private var viewRaw: String
    @AppStorage private var sortRaw: String
    @AppStorage("library.swipeHintSeen") private var hintSeen = false
    @State private var status: ListStatus?
    @State private var formatId = LibraryFormat.all.id
    @State private var searching = false
    @State private var query = ""
    @State private var statusFor: LibraryEntry?
    @State private var rateFor: LibraryEntry?

    init(media: MediaKind) {
        self.media = media
        _viewRaw = AppStorage(wrappedValue: LibraryViewMode.rows.rawValue, "library.view." + media.rawValue)
        _sortRaw = AppStorage(wrappedValue: LibrarySort.updated.rawValue, "library.sort." + media.rawValue)
    }

    private var mode: LibraryViewMode { LibraryViewMode(rawValue: viewRaw) ?? .rows }
    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .updated }
    private var formats: [LibraryFormat] { LibraryFormat.options(for: media, in: model.library) }
    private var format: LibraryFormat { formats.first { $0.id == formatId } ?? .all }

    private var shown: [LibraryEntry] {
        LibraryLists.shown(model.library, media: media, status: status, format: format, query: query, sort: sort)
    }

    var body: some View {
        Group {
            if mode == .rows {
                rowsList
            } else {
                coversGrid
            }
        }
        .pageBackground()
        .navigationTitle(media.plural)
        .navigationBarTitleDisplayMode(.inline)
        .modifier(LibraryToolbarSearch(on: $searching, text: $query, prompt: "Search \(media.plural)"))
        .onChange(of: searching) { _, on in if !on { query = "" } }
        .toolbar { toolbar }
        .confirmationDialog("Status", isPresented: present($statusFor), titleVisibility: .visible,
                            presenting: statusFor) { e in
            ForEach(ListStatus.ordered) { s in
                Button(s.label(e.media)) { model.change(e.id, LibraryPatch(status: s)) }
            }
        }
        .confirmationDialog("Rate", isPresented: present($rateFor), titleVisibility: .visible,
                            presenting: rateFor) { e in
            ForEach((1...10).reversed(), id: \.self) { n in
                Button("\(n)") { model.change(e.id, LibraryPatch(score: n * 10)) }
            }
            if e.score != nil {
                Button("No score", role: .destructive) { model.change(e.id, LibraryPatch(score: -1)) }
            }
        }
    }

    private func present(_ item: Binding<LibraryEntry?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }

    // MARK: the header (title menu, summary and chips)

    /// the big title is the menu (35): a plain Menu in the page, so it opens on a tap and its items are buttons
    /// (the Menu keeps its own size, so a tap on the empty space to its right doesn't count as opening it)
    private var header: some View {
        HStack(spacing: 0) {
            Menu { titleMenu } label: {
                HStack(spacing: 10) {
                    Text(media.plural).font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.ink)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.inkSoft)
                        .frame(width: 28, height: 28)
                        .background(Theme.raised, in: Circle())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(media.plural)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Switch media, your lists and the view")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var summary: some View {
        Text(LibraryLists.summary(model.library, media: media))
            .font(.system(size: 14)).foregroundStyle(Theme.inkMuted).numbers()
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.pad)
    }

    private var chips: some View {
        LibraryStatusChips(chips: LibraryLists.chips(model.library, media: media), selection: $status)
    }

    // MARK: rows (33, 37)

    private var rowsList: some View {
        let rows = shown
        return List {
            Group {
                header
                summary.padding(.bottom, 16)
                chips.padding(.bottom, 12)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.sheet)
            if rows.isEmpty {
                empty
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.sheet)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, e in
                row(e, separator: i < rows.count - 1)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .overlay(alignment: .bottom) { hint }
    }

    private func row(_ e: LibraryEntry, separator: Bool) -> some View {
        LibraryEntryRow(entry: e, showStatus: status == nil, separator: separator,
                        open: { model.open(.title(e.id)) }, plus: { model.step(e.id) })
            .contextMenu { EntryMenu(entry: e) }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.sheet)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if LibraryLists.canStep(e) {
                    Button {
                        model.step(e.id)
                        hintSeen = true
                    } label: {
                        Label(LibraryLists.stepLabel(e), systemImage: "plus")
                    }
                    .tint(Theme.color(.current))
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    model.change(e.id, LibraryPatch(status: .dropped))
                    hintSeen = true
                } label: {
                    Label("Drop", systemImage: "xmark")
                }
                .tint(Theme.danger)
                Button {
                    rateFor = e
                    hintSeen = true
                } label: {
                    Label("Rate", systemImage: "star")
                }
                .tint(Color(hex: 0xFF9F0A))
                Button {
                    statusFor = e
                    hintSeen = true
                } label: {
                    Label("Status", systemImage: "circle.circle")
                }
                .tint(Color(hex: 0x636366))
            }
    }

    /// what the swipes do, shown on Watching until you've used one (37)
    @ViewBuilder private var hint: some View {
        if status == .current && !hintSeen && !shown.isEmpty {
            Button {
                hintSeen = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hand.draw").font(.system(size: 14, weight: .medium))
                    Text("Swipe right for +1, left for status, rate, drop")
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.raised, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.keyline, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 14)
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(query.isEmpty ? "Nothing here" : "No matches", systemImage: LibraryLists.symbol(media))
        } description: {
            Text(query.isEmpty ? "Titles you add to your \(media.plural) list show up here." : "Nothing on this list matches “\(query)”.")
        }
        .padding(.top, 30)
    }

    // MARK: covers (34)

    private var coversGrid: some View {
        let rows = shown
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                summary.padding(.bottom, 16)
                chips.padding(.bottom, 18)
                if rows.isEmpty { empty }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(rows) { e in
                        LibraryCoverCell(entry: e)
                            .onTapGesture { model.open(.title(e.id)) }
                            .contextMenu { EntryMenu(entry: e) }
                    }
                }
                .padding(.horizontal, Theme.pad)
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: menus

    /// the title's menu (35): media, your lists, rows or covers
    @ViewBuilder private var titleMenu: some View {
        Section("Show") {
            Picker("Show", selection: Binding(get: { media }, set: { switchTo($0) })) {
                ForEach(MediaKind.allCases) { m in
                    Label(m.plural, systemImage: LibraryLists.symbol(m)).tag(m)
                }
            }
            .pickerStyle(.inline)
        }
        let all = model.customLists
        Menu {
            ForEach(all) { l in
                Button(l.name) { model.open(.customList(l.id)) }
            }
        } label: {
            Label {
                Text("Your lists")
                Text("\(all.count) \(all.count == 1 ? "list" : "lists")")
            } icon: {
                Image(systemName: "list.bullet")
            }
        }
        Section("View") {
            Picker("View", selection: $viewRaw) {
                Label("Rows", systemImage: "rectangle.grid.1x2").tag(LibraryViewMode.rows.rawValue)
                Label("Covers", systemImage: "square.grid.2x2").tag(LibraryViewMode.covers.rawValue)
            }
            .pickerStyle(.inline)
        }
    }

    /// another media's list in this one's place
    private func switchTo(_ m: MediaKind) {
        guard m != media else { return }
        var path = model.path(model.tab)
        if let i = path.lastIndex(of: .list(media)) { path[i] = .list(m) } else { path.append(.list(m)) }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { model.setPath(model.tab, path) }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        // the page's own header is the title (and its menu); the bar stays clear like the mockup's
        ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                searching = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Search")
            Menu {
                sortMenu
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort")
            Button {
                viewRaw = mode.other.rawValue
            } label: {
                Image(systemName: mode.other.symbol)
            }
            .accessibilityLabel(mode == .rows ? "Show covers" : "Show rows")
        }
    }

    /// sort and format (36)
    @ViewBuilder private var sortMenu: some View {
        Section("Sort by") {
            Picker("Sort by", selection: $sortRaw) {
                ForEach(LibrarySort.allCases) { s in
                    Label(s.label, systemImage: s.symbol).tag(s.rawValue)
                }
            }
            .pickerStyle(.inline)
        }
        if formats.count > 1 {
            Section("Format") {
                Picker("Format", selection: $formatId) {
                    ForEach(formats) { f in
                        Text(f.label).tag(f.id)
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }
}
