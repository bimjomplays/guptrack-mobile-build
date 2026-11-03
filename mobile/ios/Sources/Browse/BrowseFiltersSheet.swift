import SwiftUI

/// Filters (13): sort, genres (and tags where the media has them), years, season, format, status and score. Edits a
/// draft; ✓ or "Show N results" keeps it, Reset clears it. The count is the server's answer for the draft.
struct BrowseFiltersSheet: View {
    let media: MediaKind

    @Environment(AppModel.self) private var model
    @AppStorage(BrowseFilterStore.key) private var saved: String = BrowseFilterStore.initial
    @State private var draft: BrowseFilters
    @State private var facets: Facets?
    @State private var preview: BrowseResultsPage?

    init(media: MediaKind) {
        self.media = media
        let s = UserDefaults.standard.string(forKey: BrowseFilterStore.key) ?? BrowseFilterStore.initial
        _draft = State(initialValue: BrowseFilterStore.get(s, media))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    sortSection
                    picks("Genres", facets?.genres ?? draft.genres, draft.genres) { draft.toggleGenre($0) }
                    yearSection
                    if BrowseFilters.hasSeason(media) { seasonSection }
                    single("Format", Catalog.formats(media), $draft.format) { $0 }
                    if Catalog.statuses(media).count > 1 {
                        single("Status", Catalog.statuses(media), $draft.status) { s in
                            Catalog.statusLabel(s, media)
                        }
                    }
                    if let tags = facets?.tags, !tags.isEmpty {
                        picks("Tags", Array(tags.prefix(30)), draft.tags) { draft.toggleTag($0) }
                    }
                    scoreSection
                }
                .padding(.horizontal, Theme.pad)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            // "Show N results" stays at the foot while the choices scroll (13)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(draft.isEmpty ? "Show results" : (preview?.showText ?? "Show results")) { keep() }
                    .buttonStyle(.capsule(.tint, .large, full: true))
                    .numbers()
                    .padding(.horizontal, Theme.pad)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(Theme.sheet)
            }
            .pageBackground()
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { draft = BrowseFilters() }
                        .disabled(draft == BrowseFilters())
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { keep() }
                        .accessibilityLabel("Done")
                }
            }
        }
        .presentationDetents([.large])
        .task {
            facets = try? await model.api.browseFacets(media)
        }
        .task(id: draft.encoded) {
            // a short pause so each tap doesn't ask the server
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            preview = try? await model.api.browseTitles(media, draft)
        }
    }

    private func keep() {
        saved = BrowseFilterStore.set(saved, media, draft)
        model.sheet = nil
    }

    // MARK: sections

    private func header(_ title: String, _ value: String? = nil) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
            Spacer()
            if let value {
                Text(value).font(.system(size: 15)).foregroundStyle(Theme.inkMuted).numbers()
            }
        }
        .padding(.bottom, 12)
    }

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Sort by")
            Picker("Sort by", selection: Binding(get: { draft.sort ?? .popular }, set: { draft.sort = $0 })) {
                ForEach(BrowseFilters.Sort.allCases) { s in Text(s.label).tag(s) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func picks(_ title: String, _ choices: [String], _ picked: [String],
                       toggle: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(title, picked.isEmpty ? "Any" : "\(picked.count) selected")
            BrowseFlowLayout(spacing: 8) {
                ForEach(choices, id: \.self) { c in
                    BrowsePick(text: c, on: picked.contains(c)) { toggle(c) }
                }
            }
        }
    }

    /// one choice or none (tap the picked one again to clear it)
    private func single<V: Hashable>(_ title: String, _ choices: [V], _ picked: Binding<V?>,
                                     label: @escaping (V) -> String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(title, picked.wrappedValue.map(label) ?? "Any")
            BrowseFlowLayout(spacing: 8) {
                ForEach(choices, id: \.self) { c in
                    BrowsePick(text: label(c), on: picked.wrappedValue == c) {
                        picked.wrappedValue = picked.wrappedValue == c ? nil : c
                    }
                }
            }
        }
    }

    private var yearSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Year", draft.yearLabel)
            BrowseYearSlider(bounds: BrowseFilters.firstYear...BrowseFilters.lastYear,
                             range: Binding(get: { draft.yearRange }, set: { draft.setYears($0) }))
                .padding(.vertical, 4)
            HStack {
                Text(String(BrowseFilters.firstYear))
                Spacer()
                Text(String(BrowseFilters.lastYear))
            }
            .font(.system(size: 13)).foregroundStyle(Theme.inkMuted).numbers()
            .padding(.top, 6)
        }
    }

    private var seasonSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Season")
            Picker("Season", selection: Binding(get: { draft.season?.rawValue ?? "" },
                                                set: { draft.season = CatalogSeason(rawValue: $0) })) {
                Text("Any").tag("")
                ForEach(CatalogSeason.allCases, id: \.self) { s in Text(s.label).tag(s.rawValue) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Score")
            Picker("Score", selection: Binding(get: { draft.score ?? 0 },
                                               set: { draft.score = $0 == 0 ? nil : $0 })) {
                Text("Any").tag(0.0)
                ForEach(BrowseFilters.scoreSteps, id: \.self) { s in Text("\(Format.trim(s))+").tag(s) }
            }
            .pickerStyle(.segmented)
        }
    }
}
