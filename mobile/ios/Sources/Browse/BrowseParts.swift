import SwiftUI

// Pieces the Browse screens share (11-15): a card's caption, the add button, the selectable capsule of the filters,
// a wrapping layout for capsules, the year range slider and a title row with its status.

/// your status (dot + label), the score, or what it is, under a card or in a row
struct BrowseCaptionView: View {
    let caption: BrowseCaption

    var body: some View {
        switch caption {
        case .status(let s, let m):
            HStack(spacing: 5) {
                StatusDot(status: s, size: 7)
                Text(s.label(m)).fontWeight(.medium).foregroundStyle(Theme.inkSoft)
            }
        case .score(let v, let year):
            HStack(spacing: 6) {
                ScoreLabel(value: v, muted: true)
                if let year { Text(String(year)).numbers() }
            }
        case .text(let t):
            Text(t)
        }
    }
}

/// A poster card for a Browse shelf: opens the title, its caption is your status or the score; a long press shows
/// the list menu when it's on your list.
struct BrowseCard: View {
    let title: Title
    var withYear = false

    @Environment(AppModel.self) private var model

    var body: some View {
        let e = model.entry(title.id)
        NavigationLink(value: Route.title(title.id)) {
            PosterCard(url: title.cover, title: title.name) {
                BrowseCaptionView(caption: BrowseCaption.of(title, entry: e, withYear: withYear))
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let e {
                EntryMenu(entry: e)
            } else {
                BrowseAddButton(title: title)
            }
        }
    }
}

/// "+ Plan to Watch": puts a title that isn't on your list on it
struct BrowseAddButton: View {
    let title: Title

    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.change(title.id, BrowseAdd.patch, title: title)
        } label: {
            Label(BrowseAdd.label(title.media), systemImage: "plus")
        }
    }
}

/// the status pill when the title is on your list, else the small "+ Plan to Watch" button (rows, top hit)
struct BrowseStatusControl: View {
    let title: Title

    @Environment(AppModel.self) private var model

    var body: some View {
        if let e = model.entry(title.id) {
            StatusPill(status: e.status, media: e.media, small: true) { s in
                model.change(e.id, LibraryPatch(status: s))
            }
        } else {
            Button {
                model.change(title.id, BrowseAdd.patch, title: title)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                    Text(BrowseAdd.label(title.media)).font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(Theme.fill, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BrowseAdd.label(title.media))
        }
    }
}

/// A selectable capsule of the filters sheet: brand-tinted with a check when on.
struct BrowsePick: View {
    let text: String
    let on: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)) }
                Text(text).lineLimit(1)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(on ? Theme.brandSoft : Theme.ink)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(on ? Theme.brand.opacity(0.2) : Theme.fill, in: Capsule())
            .overlay { if on { Capsule().strokeBorder(Theme.brand.opacity(0.45), lineWidth: 0.5) } }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// capsules that wrap onto the next line
struct BrowseFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, width: bounds.width)
        for row in rows {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var items: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width && !row.items.isEmpty {
                rows.append(row)
                row = Row(items: [], y: row.y + row.height + spacing, width: 0, height: 0)
                row.items = [i]
                row.width = size.width
                row.height = size.height
            } else {
                row.items.append(i)
                row.width = needed
                row.height = max(row.height, size.height)
            }
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

/// Two knobs on one track (the filters sheet's Year): the brand line between them.
struct BrowseYearSlider: View {
    let bounds: ClosedRange<Int>
    @Binding var range: ClosedRange<Int>

    private let knob = CGSize(width: 38, height: 26)

    var body: some View {
        GeometryReader { g in
            let track = max(1, g.size.width - knob.width)
            let span = CGFloat(max(1, bounds.upperBound - bounds.lowerBound))
            let lo = CGFloat(range.lowerBound - bounds.lowerBound) / span * track
            let hi = CGFloat(range.upperBound - bounds.lowerBound) / span * track
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track).frame(height: 4)
                Capsule().fill(Theme.brand)
                    .frame(width: max(0, hi - lo), height: 4)
                    .offset(x: lo + knob.width / 2)
                knobView
                    .offset(x: lo)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("yearTrack")).onChanged { v in
                        let year = value(at: v.location.x - knob.width / 2, track: track, span: span)
                        range = min(year, range.upperBound)...range.upperBound
                    })
                    .accessibilityLabel("From")
                    .accessibilityValue(String(range.lowerBound))
                knobView
                    .offset(x: hi)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("yearTrack")).onChanged { v in
                        let year = value(at: v.location.x - knob.width / 2, track: track, span: span)
                        range = range.lowerBound...max(year, range.lowerBound)
                    })
                    .accessibilityLabel("To")
                    .accessibilityValue(String(range.upperBound))
            }
            .frame(height: knob.height)
            .coordinateSpace(name: "yearTrack")
        }
        .frame(height: 28)
    }

    private var knobView: some View {
        Capsule().fill(Color.white)
            .frame(width: knob.width, height: knob.height)
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            .contentShape(Rectangle().inset(by: -8))
    }

    private func value(at x: CGFloat, track: CGFloat, span: CGFloat) -> Int {
        let f = min(1, max(0, x / track))
        return bounds.lowerBound + Int((f * span).rounded())
    }
}

/// A title in a list (season chart, filter results): poster, name, facts, the airing line, then status or add.
struct BrowseTitleRow: View {
    let title: Title
    var separator = true

    @Environment(AppModel.self) private var model

    var body: some View {
        let t = title
        HStack(alignment: .top, spacing: 14) {
            Poster(url: t.cover, width: 58, radius: 8, flat: true)
                .padding(.vertical, 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(t.name).font(.rowTitle).foregroundStyle(Theme.ink).lineLimit(1)
                factsLine.padding(.top, 1)
                if let air = SeasonChart.airing(t) {
                    HStack(spacing: 5) {
                        Image(systemName: air.symbol).font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.inkMuted)
                        Text(air.text).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
                            .numbers().lineLimit(1)
                    }
                    .padding(.top, 3)
                }
                BrowseStatusControl(title: t).padding(.top, 8)
            }
            .padding(.top, 11).padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { if separator { Hairline() } }
        }
        .padding(.horizontal, Theme.pad)
        .contentShape(Rectangle())
        .onTapGesture { model.open(.title(t.id)) }
        .contextMenu {
            if let e = model.entry(t.id) { EntryMenu(entry: e) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open") { model.open(.title(t.id)) }
    }

    private var factsLine: some View {
        let facts = SeasonChart.facts(title)
        let genres = SeasonChart.genres(title)
        let first = Text(facts).foregroundStyle(Theme.inkSoft)
        let rest = Text(genres.isEmpty ? "" : " · " + genres).foregroundStyle(Theme.inkMuted)
        return Text("\(first)\(rest)")
            .font(.caption14)
            .lineLimit(1)
    }
}
