import SwiftUI

/// Filters (13): sort, genres, years, season, format, status (score for TV, films and books). Edits a draft; ✓ or
/// "Show N results" keeps it, Reset clears it. The count is the demo catalogue with the draft applied.
struct BrowseFiltersSheet: View {
    let media: MediaKind

    @Environment(AppModel.self) private var model
    @AppStorage(BrowseFilterStore.key) private var saved: String = BrowseFilterStore.initial
    @State private var draft: BrowseFilters
    @State private var pool: [Title]?

    init(media: MediaKind) {
        self.media = media
        let s = UserDefaults.standard.string(forKey: BrowseFilterStore.key) ?? BrowseFilterStore.initial
        _draft = State(initialValue: BrowseFilterStore.get(s, media))
    }

    private var count: Int? { pool.map { draft.apply($0).count } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    sortSection
                    picks("Genres", BrowseFilters.genreChoices(media), draft.genres) { draft.toggleGenre($0) }
                    yearSection
                    if BrowseFilters.hasSeason(media) { seasonSection }
                    if !BrowseFilters.formatChoices(media).isEmpty {
                        picks("Format", BrowseFilters.formatChoices(media), draft.formats) { draft.toggleFormat($0) }
                    }
                    if !BrowseFilters.statusChoices(media).isEmpty {
                        picks("Status", BrowseFilters.statusChoices(media), draft.statuses) { draft.toggleStatus($0) }
                    }
                    if BrowseFilters.hasScore(media) { scoreSection }
                    Button(count.map { "Show \($0) results" } ?? "Show results") { keep() }
                        .buttonStyle(.capsule(.tint, .large, full: true))
                        .numbers()
                        .padding(.top, 4)
                }
                .padding(.horizontal, Theme.pad)
                .padding(.top, 12)
                .padding(.bottom, 30)
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
            pool = try? await model.api.browseTitles(media, BrowseFilters())
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
            Picker("Sort by", selection: $draft.sort) {
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
            Picker("Season", selection: Binding(get: { draft.season ?? "" },
                                                set: { draft.season = $0.isEmpty ? nil : $0 })) {
                Text("Any").tag("")
                ForEach(BrowseFilters.seasons, id: \.self) { s in Text(s).tag(s) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Score")
            Picker("Score", selection: Binding(get: { draft.minScore ?? 0 },
                                               set: { draft.minScore = $0 == 0 ? nil : $0 })) {
                Text("Any").tag(0.0)
                ForEach(BrowseFilters.scoreSteps, id: \.self) { s in Text("\(Int(s))+").tag(s) }
            }
            .pickerStyle(.segmented)
        }
    }
}
