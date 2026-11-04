import SwiftUI

/// Search results (15) as their own page (route search/<query>); Browse shows the same content in place while you
/// type.
struct SearchResultsView: View {
    let query: String

    @State private var text: String
    @State private var shown: String

    init(query: String) {
        self.query = query
        _text = State(initialValue: query)
        _shown = State(initialValue: query)
    }

    var body: some View {
        BrowseSearchContent(query: shown)
            .pageBackground()
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Anime, shows, films, manga, books")
            .autocorrectionDisabled()
            .onSubmit(of: .search) { shown = text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

/// One search: scope chips, the top hit, then the server's groups (each media, characters, people).
struct BrowseSearchContent: View {
    let query: String

    var body: some View {
        ScrollView {
            PageLoader(id: query, load: { [query] api in try await api.search(query) }) { r in
                BrowseSearchList(results: r)
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

struct BrowseSearchList: View {
    let results: SearchResults

    @State private var scope = "All"

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: results.query)
                .padding(.top, 60)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                scopes
                if scope == "All", let top = results.top {
                    BrowseTopHit(hit: top).padding(.top, 18)
                }
                ForEach(results.shown(scope), id: \.title) { g in
                    group(g).padding(.top, 24)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
            .onChange(of: results.query) { scope = "All" }
        }
    }

    private var scopes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(results.scopes, id: \.0) { item in
                    let s = item.0
                    Button {
                        scope = s
                    } label: {
                        ChipLabel(text: s, on: scope == s, count: item.1.map(String.init))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(scope == s ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.pad)
        }
        .scrollClipDisabled()
    }

    private func group(_ g: SearchGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(g.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                // under All a group shows its first two; See all opens its chip
                if scope == "All", let n = results.groups.first(where: { $0.title == g.title })?.hits.count,
                   n > min(2, g.hits.count) {
                    Button { scope = g.title } label: {
                        HStack(spacing: 3) {
                            Text("See all \(n)")
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.brandSoft)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.bottom, 4)
            ForEach(scope == "All" ? Array(g.hits.prefix(2)) : g.hits, id: \.self) { h in
                if let t = h.title {
                    BrowseSearchRow(hit: h, title: t)
                } else {
                    BrowsePersonRow(hit: h)
                }
            }
        }
    }
}

/// The best match: poster, "Top hit · Anime · TV · 2022", the name, then your status or the add button.
struct BrowseTopHit: View {
    let hit: SearchHit

    @Environment(AppModel.self) private var model

    var body: some View {
        if let t = hit.title {
            HStack(alignment: .center, spacing: 14) {
                Poster(url: t.cover, width: 54, radius: 8, flat: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(SearchResults.topLine(hit)).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.inkMuted).numbers().lineLimit(1)
                    Text(t.name).font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(2)
                    BrowseStatusControl(title: t).padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Theme.pad)
            .contentShape(Rectangle())
            .onTapGesture { model.open(.title(t.id)) }
            .contextMenu { if let e = model.entry(t.id) { EntryMenu(entry: e) } }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Open") { model.open(.title(t.id)) }
        }
    }
}

/// a title in the results: 40pt cover, name, the server's note, your status on the right
struct BrowseSearchRow: View {
    let hit: SearchHit
    let title: Title

    @Environment(AppModel.self) private var model

    var body: some View {
        let t = title
        NavigationLink(value: Route.title(t.id)) {
            HStack(spacing: 12) {
                Poster(url: t.cover, width: 40, radius: 6, flat: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name).font(.rowTitle).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(hit.note).font(.caption14).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        .numbers()
                }
                Spacer(minLength: 8)
                if let s = t.score {
                    ScoreLabel(value: Format.trim(s), size: 14)
                }
                if let e = model.entry(t.id) {
                    StatusDot(status: e.status)
                        .accessibilityLabel(e.status.label(e.media))
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let e = model.entry(t.id) { EntryMenu(entry: e) } else { BrowseAddButton(title: t) }
        }
    }
}

/// a character or person in the results: a round picture, the name and the server's note
struct BrowsePersonRow: View {
    let hit: SearchHit

    var body: some View {
        let row = HStack(spacing: 12) {
            Artwork(url: hit.image)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.keyline, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.name).font(.rowTitle).foregroundStyle(Theme.ink).lineLimit(1)
                Text(hit.note).font(.caption14).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        if let r = hit.route {
            NavigationLink(value: r) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}
