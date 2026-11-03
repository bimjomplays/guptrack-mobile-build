import SwiftUI

/// The line under "Your list": when the next episode airs (anime), what's up next (TV), the tagline and trailer (films).
struct TitleInfoLine: View {
    let page: TitlePage

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    private var t: Title { page.title }

    var body: some View {
        Group {
            if let next = t.next, t.media == .anime || t.media == .manga {
                let parts = TitleListText.airing(next, media: t.media)
                line("calendar", parts.0, parts.1)
            } else if t.media == .tv, let up = upNext {
                Button { model.open(.season(t.id, up.season)) } label: {
                    line("play.circle", "Up next", " · S\(up.season) E\(up.episode.number) “\(up.episode.name)”"
                         + (up.episode.runtime.map { " · " + $0 } ?? ""))
                }
                .buttonStyle(.plain)
            } else if t.media == .movie, page.tagline != nil || page.trailer != nil {
                tagline
            }
        }
        .padding(.horizontal, Theme.pad)
    }

    /// the next episode on the list's progress
    private var upNext: (season: Int, episode: TVSeason.Episode)? {
        guard let e = model.entry(t.id), let seasons = page.seasons,
              let pos = TVProgress.position(e.progress, seasons), let n = pos.next,
              let ep = seasons.first(where: { $0.number == pos.season })?.episodes?.first(where: { $0.number == n })
        else { return nil }
        return (pos.season, ep)
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
            if let tl = page.tagline {
                Text(tl).font(.system(size: 15).italic()).foregroundStyle(Theme.inkSoft).lineLimit(2)
            }
            Spacer(minLength: 0)
            if let url = page.trailer {
                Button { openURL(url) } label: { Label("Trailer", systemImage: "play.fill") }
                    .buttonStyle(.capsule(.tone, .small))
            }
        }
    }
}

/// Everything under the top: story, tags, makers, seasons, characters, cast, crew, related, scores, details,
/// reviews, more like this. Each shows only when the page has it.
struct TitleSections: View {
    let page: TitlePage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let story = page.story {
                TitleHeading(page.storyHeading).sectionGap(26)
                MoreText(text: story, lines: 4)
            }
            if !page.tags.isEmpty {
                TitleTags(tags: page.tags).padding(.top, page.story == nil ? 26 : 14)
            }
            if let staff = page.staff, !staff.isEmpty {
                TitleMakers(people: staff).padding(.top, 18)
            }
            if let seasons = page.seasons, !seasons.isEmpty {
                TitleSeasons(page: page, seasons: seasons).sectionGap()
            }
            if let chars = page.characters, !chars.isEmpty {
                TitleCharacters(characters: chars).sectionGap()
            }
            if let cast = page.cast, !cast.isEmpty {
                TitleCast(cast: cast).sectionGap()
            }
            if let crew = page.crew, !crew.isEmpty {
                TitleCrew(crew: crew).sectionGap()
            }
            if let rel = page.relations, !rel.isEmpty {
                TitleRelated(page: page, relations: rel).sectionGap()
            }
            if page.hasScoreAverage {
                TitleScoreAverage(page: page).sectionGap()
            }
            TitleDetails(page: page).sectionGap()
            TitleReviewsRow(page: page).sectionGap(22)
            if let recs = page.recommendations, !recs.isEmpty {
                TitleMoreLikeThis(titles: recs).sectionGap()
            }
        }
    }
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
    let people: [TitlePage.Credit]

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            ForEach(people, id: \.self) { p in
                Button { if let r = p.route { model.open(r) } } label: {
                    HStack(spacing: 12) {
                        Artwork(url: p.image).frame(width: 44, height: 44).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.rowTitle).foregroundStyle(Theme.ink)
                            if let role = p.role { Text(role).font(.system(size: 13)).foregroundStyle(Theme.inkMuted) }
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
