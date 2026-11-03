import SwiftUI

/// The line under "Your list": when the next episode airs (anime), what's up next (TV), the tagline and trailer (films).
struct TitleInfoLine: View {
    let page: TitlePage

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    private var t: Title { page.title }

    var body: some View {
        Group {
            if let next = page.nextEpisode, t.media == .anime || t.media == .manga {
                line("calendar", "Next episode", " · " + next)
            } else if t.media == .tv, let up = upNext {
                Button { model.open(.season(t.id, up.season)) } label: {
                    line("play.circle", "Up next", " · S\(up.season) E\(up.episode)")
                }
                .buttonStyle(.plain)
            } else if t.media == .movie, page.trailer != nil {
                tagline
            }
        }
        .padding(.horizontal, Theme.pad)
    }

    /// the next episode on the list's progress (the answer's seasons carry counts, not episodes)
    private var upNext: (season: Int, episode: Int)? {
        guard let e = model.entry(t.id), let pos = TVProgress.position(e.progress, page.seasons), let n = pos.next
        else { return nil }
        return (pos.season, n)
    }

    private func line(_ symbol: String, _ head: String, _ rest: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(Theme.inkSoft)
            (Text(head).fontWeight(.semibold).foregroundStyle(Theme.ink) + Text(rest).foregroundStyle(Theme.inkSoft))
                .font(.system(size: 14)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var tagline: some View {
        HStack(spacing: 12) {
            if let url = page.trailer {
                Button { openURL(url) } label: { Label("Trailer", systemImage: "play.fill") }
                    .buttonStyle(.capsule(.tone, .small))
            }
            Spacer(minLength: 0)
        }
    }
}

/// Everything under the top: story, tags, makers, seasons, characters, cast, crew, related, scores, details,
/// reviews, more like this. Each shows only when the page has it.
struct TitleSections: View {
    let page: TitlePage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let story = page.story() {
                TitleHeading(page.storyHeading).sectionGap(26)
                MoreText(text: story, lines: 4)
            }
            if !page.tags.isEmpty {
                TitleTags(tags: page.tags).padding(.top, page.story() == nil ? 26 : 14)
            }
            // a manga's or book's makers sit under the story; everyone else's staff is a list further down
            if makersOnTop, !page.staff.isEmpty {
                TitleMakers(people: page.staff).padding(.top, 18)
            }
            if !page.seasons.isEmpty {
                TitleSeasons(page: page, seasons: page.seasons).sectionGap()
            }
            if !page.characters.isEmpty {
                TitleCharacters(characters: page.characters).sectionGap()
            }
            if !page.cast.isEmpty {
                TitleCast(cast: page.cast).sectionGap()
            }
            if !makersOnTop, !page.staff.isEmpty {
                TitleCrew(crew: page.staff, heading: page.title.media == .anime ? "Staff" : "Crew").sectionGap()
            }
            if !page.relations.isEmpty {
                TitleRelated(page: page, relations: page.relations).sectionGap()
            }
            if page.averageText != nil {
                TitleScoreAverage(page: page).sectionGap()
            }
            TitleDetails(page: page).sectionGap()
            TitleReviewsRow(page: page).sectionGap(22)
            if !page.recommendations.isEmpty {
                TitleMoreLikeThis(title: "More like this", titles: page.recommendations).sectionGap()
            }
            ForEach(page.more, id: \.self) { m in
                TitleMoreLikeThis(title: m.title, titles: m.titles.map(\.app), route: m.ref?.route).sectionGap()
            }
        }
    }

    private var makersOnTop: Bool { page.title.media == .manga || page.title.media == .book }
}

/// a section's 20pt title, with an optional count
struct TitleHeading: View {
    let title: String
    var count: Int?

    init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let count {
                Text(Format.grouped(count)).font(.system(size: 15)).foregroundStyle(Theme.inkMuted).numbers()
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.bottom, 10)
    }
}

/// genres or a book's subjects, wrapping
private struct TitleTags: View {
    let tags: [String]

    var body: some View {
        TitleFlow(spacing: 8) {
            ForEach(tags, id: \.self) { TagLabel(text: $0) }
        }
        .padding(.horizontal, Theme.pad)
    }
}

/// a left-to-right flow that wraps to new lines
struct TitleFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var cur: (items: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            let w = cur.items.isEmpty ? s.width : cur.width + spacing + s.width
            if w > maxWidth, !cur.items.isEmpty {
                rows.append(cur)
                cur = ([i], s.width, s.height)
            } else {
                cur = (cur.items + [i], w, max(cur.height, s.height))
            }
        }
        if !cur.items.isEmpty { rows.append(cur) }
        return rows
    }
}

/// a manga's or book's makers: round picture, name, role, a chevron to their page
private struct TitleMakers: View {
    let people: [Credit]

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            ForEach(people, id: \.self) { c in
                let p = c.person
                Button { if let r = p.route { model.open(r) } } label: {
                    HStack(spacing: 12) {
                        Artwork(url: p.image).frame(width: 44, height: 44).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.rowTitle).foregroundStyle(Theme.ink)
                            if !c.role.isEmpty { Text(c.role).font(.system(size: 13)).foregroundStyle(Theme.inkMuted) }
                        }
                        Spacer()
                        if p.route != nil {
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.inkFaint)
                        }
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(p.route == nil)
            }
        }
        .padding(.horizontal, Theme.pad)
    }
}
