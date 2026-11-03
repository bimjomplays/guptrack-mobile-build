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

/// One search: scope chips, the top hit, then a group per media and people.
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

    @State private var scope: SearchResults.Scope = .all

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: results.query)
                .padding(.top, 60)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                scopes
                if scope == .all, let top = results.top {
                    BrowseTopHit(title: top).padding(.top, 18)
                }
                ForEach(results.shown(scope)) { g in
                    group(g).padding(.top, 24)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
            .onChange(of: results.query) { scope = .all }
        }
    }

    private var scopes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(results.scopes, id: \.0) { item in
                    let (s, n) = item
                    Button {
                        scope = s
                    } label: {
                        ChipLabel(text: s.label, on: scope == s, count: n.map(String.init))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(scope == s ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.pad)
        }
        .scrollClipDisabled()
    }

    private func group(_ g: SearchResults.Group) -> some View {
        let more = scope == .all && g.total > g.titles.count + g.people.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text(g.scope.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if more {
                    Button {
                        scope = g.scope
                    } label: {
                        HStack(spacing: 3) {
                            Text("See all \(g.total)")
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                        }
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.brandSoft)
                    .buttonStyle(.plain)
                    .numbers()
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.bottom, 4)
            ForEach(g.titles) { t in BrowseSearchRow(title: t) }
            ForEach(g.people) { p in BrowsePersonRow(person: p) }
        }
    }
}

/// The best match: poster, "Top hit · Anime · 2022", the name, its facts and score, then your status or the add button.
struct BrowseTopHit: View {
    let title: Title

    @Environment(AppModel.self) private var model

    var body: some View {
        let t = title
        HStack(alignment: .center, spacing: 14) {
            Poster(url: t.cover, width: 54, radius: 8, flat: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(SearchResults.topLine(t)).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted).numbers()
                Text(t.name).font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(2)
                HStack(spacing: 6) {
                    Text(SearchResults.topFacts(t)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    if let s = t.score { ScoreLabel(value: Format.average(s), muted: true) }
                }
                .font(.caption14)
                BrowseStatusControl(title: t).padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, Theme.pad)
        .contentShape(Rectangle())
        .onTapGesture { model.open(.title(t.id)) }
        .contextMenu { if let e = model.entry(t.id) { EntryMenu(entry: e) } }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open") { model.open(.title(t.id)) }
    }
}

/// a title in the results: 40pt cover, name, caption, score on the right
struct BrowseSearchRow: View {
    let title: Title

    @Environment(AppModel.self) private var model

    var body: some View {
        let t = title
        NavigationLink(value: Route.title(t.id)) {
            HStack(spacing: 12) {
                Poster(url: t.cover, width: 40, radius: 6, flat: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name).font(.rowTitle).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(SearchResults.caption(t)).font(.caption14).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        .numbers()
                }
                Spacer(minLength: 8)
                if let e = model.entry(t.id) {
                    StatusDot(status: e.status)
                        .accessibilityLabel(e.status.label(e.media))
                } else if let s = t.score {
                    ScoreLabel(value: Format.average(s), muted: true)
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

/// someone in the results: a round picture, the name and what they do
struct BrowsePersonRow: View {
    let person: SearchResults.Person

    var body: some View {
        let row = HStack(spacing: 12) {
            Artwork(url: person.image)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.keyline, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.rowTitle).foregroundStyle(Theme.ink).lineLimit(1)
                Text(person.caption).font(.caption14).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        if let r = person.route {
            NavigationLink(value: r) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}
