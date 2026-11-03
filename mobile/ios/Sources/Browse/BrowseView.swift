import SwiftUI

/// Browse (11, 12): search pinned under the title, the media switch, filter chips, then the media's shelves (TV and
/// Movies open with a feature card). Typing shows search results in place; filters (chips or the sheet) or a shelf's
/// header show the catalogue as a list.
struct BrowseView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(BrowseFilterStore.key) private var saved: String = BrowseFilterStore.initial
    @State private var media: MediaKind = .anime
    @State private var text = ""
    @State private var query = ""
    /// a shelf whose header was tapped: the whole catalogue in its order
    @State private var expanded: BrowsePage.Shelf?

    private var filters: BrowseFilters { BrowseFilterStore.get(saved, media) }

    var body: some View {
        content
            .pageBackground()
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Anime, shows, films, manga, books")
            .autocorrectionDisabled()
            .task(id: text) {
                // a short pause so each key doesn't send a search
                try? await Task.sleep(for: .milliseconds(text.isEmpty ? 0 : 250))
                guard !Task.isCancelled else { return }
                query = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.sheet = .browseFilters(media)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Filters")
                }
            }
            .onChange(of: media) { expanded = nil }
    }

    @ViewBuilder
    private var content: some View {
        if !query.isEmpty && !text.isEmpty {
            BrowseSearchContent(query: query)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BrowseMediaSwitch(media: $media)
                        .padding(.horizontal, Theme.pad)
                    BrowseChips(media: media, saved: $saved)
                        .padding(.top, 14)
                    if !filters.isEmpty || expanded != nil {
                        results
                    } else {
                        shelves
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
    }

    private var shelves: some View {
        PageLoader(id: media.rawValue, load: { [media] api in try await api.browsePage(media) }) { page in
            VStack(alignment: .leading, spacing: 0) {
                if let f = page.feature {
                    BrowseFeatureCard(feature: f)
                        .padding(.horizontal, Theme.pad)
                        .padding(.top, 22)
                }
                ForEach(page.shelves) { s in
                    shelf(s, media: page.media).sectionGap(page.feature == nil && s.id == page.shelves.first?.id ? 24 : 32)
                }
            }
        }
    }

    private func shelf(_ s: BrowsePage.Shelf, media m: MediaKind) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(s.title, sub: s.note, action: { open(s) })
            Shelf {
                ForEach(s.titles) { t in
                    BrowseCard(title: t, withYear: m == .tv || m == .movie)
                }
            }
        }
    }

    /// See all: the season chart, or the shelf's own filter as a list
    private func open(_ s: BrowsePage.Shelf) {
        if s.chart {
            model.open(.seasonChart)
        } else {
            expanded = s
        }
    }

    // MARK: the catalogue as a list

    private var results: some View {
        let f = expanded?.filter ?? filters
        let key = "\(media.rawValue)|\(f.encoded)"
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text(expanded?.title ?? "Results").font(.section).foregroundStyle(Theme.ink)
                Spacer()
                Button("Clear") {
                    expanded = nil
                    saved = BrowseFilterStore.set(saved, media, BrowseFilters())
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.brandSoft)
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, 24)
            .padding(.bottom, 4)
            PageLoader(id: key, load: { [media, f] api in try await api.browseTitles(media, f) }) { first in
                BrowseResultsList(media: media, filters: f, first: first).id(key)
            }
        }
    }
}

/// The results, a page at a time: "Show more" asks for the next page while the server has one.
struct BrowseResultsList: View {
    let media: MediaKind
    let filters: BrowseFilters
    let first: BrowseResultsPage

    @Environment(AppModel.self) private var model
    @State private var extra: [Title] = []
    @State private var next: Int?
    @State private var started = false
    @State private var loading = false

    private var titles: [Title] {
        var seen = Set<String>()
        return (first.titles + extra).filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        let ts = titles
        if ts.isEmpty {
            ContentUnavailableView("Nothing matches", systemImage: "line.3.horizontal.decrease",
                                   description: Text("Try fewer filters."))
                .padding(.top, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(ts.enumerated()), id: \.element.id) { i, t in
                    BrowseTitleRow(title: t, separator: i < ts.count - 1)
                }
                if let page = started ? next : first.next {
                    Button(loading ? "Loading…" : "Show more") { Task { await more(page) } }
                        .buttonStyle(.capsule(.tone, .regular))
                        .disabled(loading)
                        .padding(.top, 18)
                }
            }
        }
    }

    private func more(_ page: Int) async {
        loading = true
        defer { loading = false }
        guard let p = try? await model.api.browseTitles(media, filters, page: page) else { return }
        extra += p.titles
        next = p.next
        started = true
    }
}

/// Anime, Manga, TV, Movies, Books
struct BrowseMediaSwitch: View {
    @Binding var media: MediaKind

    var body: some View {
        Picker("Media", selection: $media) {
            ForEach(MediaKind.allCases) { m in
                Text(m.plural).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }
}

/// The chips under the switch: sort, then a menu per filter (the sheet has them all).
struct BrowseChips: View {
    let media: MediaKind
    @Binding var saved: String

    @Environment(AppModel.self) private var model
    /// the genres the server offers for this media
    @State private var facets: Facets?

    private var f: BrowseFilters { BrowseFilterStore.get(saved, media) }

    private func edit(_ change: (inout BrowseFilters) -> Void) {
        var x = f
        change(&x)
        saved = BrowseFilterStore.set(saved, media, x)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                sortChip
                multi("Genres", facets?.genres ?? f.genres, f.genres) { x, g in x.toggleGenre(g) }
                yearChip
                if BrowseFilters.hasSeason(media) { seasonChip }
                single("Format", Catalog.formats(media), f.format, label: { $0 }) { x, v in x.format = v }
                if Catalog.statuses(media).count > 1 {
                    single("Status", Catalog.statuses(media), f.status,
                           label: { s in Catalog.statusLabel(s, media) }) { x, v in x.status = v }
                }
                scoreChip
            }
            .padding(.horizontal, Theme.pad)
        }
        .scrollClipDisabled()
        .task(id: media) {
            facets = nil
            facets = try? await model.api.browseFacets(media)
        }
    }

    private var sortLabel: String { (f.sort ?? .popular).label }

    private var sortChip: some View {
        Menu {
            Picker("Sort by", selection: Binding(get: { f.sort ?? .popular }, set: { s in edit { $0.sort = s } })) {
                ForEach(BrowseFilters.Sort.allCases) { s in Text(s.label).tag(s) }
            }
        } label: {
            ChipLabel(text: sortLabel, on: true, symbol: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort by \(sortLabel)")
    }

    private func single<V: Hashable>(_ name: String, _ choices: [V], _ picked: V?,
                                     label: @escaping (V) -> String,
                                     set: @escaping (inout BrowseFilters, V?) -> Void) -> some View {
        Menu {
            Button("Any") { edit { set(&$0, nil) } }
            ForEach(choices, id: \.self) { c in
                Button {
                    edit { set(&$0, picked == c ? nil : c) }
                } label: {
                    if picked == c { Label(label(c), systemImage: "checkmark") } else { Text(label(c)) }
                }
            }
        } label: {
            ChipLabel(text: picked.map(label) ?? name, on: picked != nil, menu: true)
        }
    }

    private func multi(_ name: String, _ choices: [String], _ picked: [String],
                       toggle: @escaping (inout BrowseFilters, String) -> Void) -> some View {
        Menu {
            ForEach(choices, id: \.self) { c in
                Button {
                    edit { toggle(&$0, c) }
                } label: {
                    if picked.contains(c) { Label(c, systemImage: "checkmark") } else { Text(c) }
                }
            }
        } label: {
            ChipLabel(text: BrowseFilters.chipText(name, picked), on: !picked.isEmpty, menu: true)
        }
        .menuActionDismissBehavior(.disabled)
    }

    private var yearChip: some View {
        let last = BrowseFilters.lastYear
        return Menu {
            Button("Any year") { edit { $0.from = nil; $0.to = nil } }
            Button("This year") { edit { $0.from = last; $0.to = nil } }
            Button("Last 5 years") { edit { $0.from = last - 4; $0.to = nil } }
            Button("2010s") { edit { $0.from = 2010; $0.to = 2019 } }
            Button("Before 2010") { edit { $0.from = nil; $0.to = 2009 } }
        } label: {
            let on = f.from != nil || f.to != nil
            ChipLabel(text: on ? f.yearLabel : "Year", on: on, menu: true)
        }
    }

    private var seasonChip: some View {
        Menu {
            Button("Any season") { edit { $0.season = nil } }
            ForEach(CatalogSeason.allCases, id: \.self) { s in
                Button(s.label) { edit { $0.season = s } }
            }
        } label: {
            ChipLabel(text: f.season?.label ?? "Season", on: f.season != nil, menu: true)
        }
    }

    private var scoreChip: some View {
        Menu {
            Button("Any score") { edit { $0.score = nil } }
            ForEach(BrowseFilters.scoreSteps, id: \.self) { s in
                Button("\(Format.trim(s))+") { edit { $0.score = s } }
            }
        } label: {
            ChipLabel(text: f.score.map(BrowseFilters.scoreText) ?? "Score", on: f.score != nil, menu: true)
        }
    }
}

/// The card on top of TV and Movies: backdrop, "Most added this week", the name, a facts line and the add button
/// (or your status when it's on your list).
struct BrowseFeatureCard: View {
    let feature: BrowsePage.Feature

    @Environment(AppModel.self) private var model

    var body: some View {
        let t = feature.title
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Artwork(url: t.banner ?? t.cover)
            .frame(maxWidth: .infinity)
            .frame(height: 230)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(feature.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    Text(t.name).font(.system(size: 28, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    Text(feature.line).font(.system(size: 15)).foregroundStyle(.white.opacity(0.8)).numbers()
                    action(t).padding(.top, 10)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                // a flat dark layer under the words (no gradient)
                .background(Color.black.opacity(0.55))
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.keyline, lineWidth: 0.5))
            .contentShape(shape)
            .onTapGesture { model.open(.title(t.id)) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(feature.label): \(t.name)")
    }

    @ViewBuilder
    private func action(_ t: Title) -> some View {
        if let e = model.entry(t.id) {
            StatusPill(status: e.status, media: e.media) { s in model.change(e.id, LibraryPatch(status: s)) }
        } else {
            Button {
                model.change(t.id, BrowseAdd.patch, title: t)
            } label: {
                Label(BrowseAdd.label(t.media), systemImage: "plus")
            }
            .buttonStyle(.capsule(.white, .regular))
        }
    }
}
