import SwiftUI

// Pieces both profiles use (41, 48): the banner with the picture and name, the Statistics block with the media
// switch, the status legend and the Last updates shelf.

/// The banner fading into the page (the approved exception to the no-gradient rule; the strength comes from
/// Settings › Profile), with the picture and the name over its foot.
struct ProfileBanner<Caption: View>: View {
    let banner: URL?
    let avatar: URL?
    let name: String
    var fade: Double = 0.7
    @ViewBuilder var caption: () -> Caption

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            art
            HStack(alignment: .bottom, spacing: 14) {
                Avatar(url: avatar, size: 88)
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    caption()
                }
                .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
                .padding(.bottom, 4)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.pad)
            .padding(.bottom, 16)
        }
        .frame(height: 300)
    }

    private var art: some View {
        let k = fade / 0.7
        return Artwork(url: banner, placeholder: Theme.panel)
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .overlay {
                LinearGradient(stops: [
                    .init(color: .black.opacity(0), location: 0.3),
                    .init(color: .black.opacity(min(1, 0.35 * k)), location: 0.65),
                    .init(color: .black.opacity(min(1, 0.55 * k)), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Theme.sheet.opacity(0), Theme.sheet], startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
            }
            .clipped()
    }
}

/// "See all ›" (or a count with its chevron) at a section header's right
struct ProfileSeeAll: View {
    var text = "See all"
    var chevron = true

    var body: some View {
        HStack(spacing: 4) {
            Text(text).numbers()
            if chevron { Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)) }
        }
        .font(.system(size: 17))
        .foregroundStyle(Theme.inkMuted)
    }
}

/// the five media as the system's segmented control
struct ProfileMediaPicker: View {
    @Binding var media: MediaKind

    var body: some View {
        Picker("Media", selection: $media) {
            ForEach(MediaKind.allCases) { m in Text(m.plural).tag(m) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.pad)
    }
}

/// Statistics on a profile (41, 48): the four columns, entries, the status bar and its legend.
struct ProfileStatsBlock<Right: View>: View {
    let summary: LibraryStats.Summary
    @ViewBuilder var right: () -> Right

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(summary.columns, id: \.label) { c in StatColumn(value: c.value, label: c.label) }
            }
            .padding(.top, 16)
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 4) {
                    Text("Entries").foregroundStyle(Theme.inkMuted)
                    Text(Format.grouped(summary.entries)).fontWeight(.semibold).foregroundStyle(Theme.ink)
                }
                Spacer()
                right()
            }
            .font(.system(size: 13))
            .numbers()
            .padding(.top, 18)
            .padding(.bottom, 8)
            if summary.entries > 0 {
                StatusBar5(counts: summary.statusCounts)
                StatusLegend(summary: summary).padding(.top, 10)
            } else {
                Text("Nothing on this list yet").font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(.horizontal, Theme.pad)
    }
}

/// "● Watching 7 4%" for each status, wrapping
struct StatusLegend: View {
    let summary: LibraryStats.Summary

    var body: some View {
        ProfileFlow(spacing: 16, lineSpacing: 6) {
            ForEach(ListStatus.ordered) { s in
                HStack(spacing: 6) {
                    StatusDot(status: s)
                    Text(s.label(summary.media)).foregroundStyle(Theme.inkMuted)
                    Text(Format.grouped(summary.count(s))).fontWeight(.semibold).foregroundStyle(Theme.ink)
                    Text(summary.percent(s)).foregroundStyle(Theme.inkMuted.opacity(0.7))
                }
                .font(.system(size: 13))
                .numbers()
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Last updates (41, 48): posters with what changed under them.
struct LastUpdatesShelf: View {
    let updates: [UserPage.Update]

    @Environment(AppModel.self) private var model

    var body: some View {
        Shelf {
            ForEach(updates) { u in
                NavigationLink(value: Route.title(u.title.id)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Poster(url: u.title.cover, width: 104, radius: 9)
                        Text(u.caption).font(.system(size: 12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                            .numbers()
                    }
                    .frame(width: 104, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(u.title.name), \(u.caption)")
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if let e = model.entry(u.title.id) { EntryMenu(entry: e) }
                }
            }
        }
    }
}

/// Rows of small views that wrap to the next line (legends).
struct ProfileFlow: Layout {
    var spacing: CGFloat = 16
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
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

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty && needed > width {
                rows.append(row)
                row = Row(items: [], y: row.y + row.height + lineSpacing)
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.items.append(i)
            row.height = max(row.height, size.height)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

extension MediaKind {
    /// the media remembered by the profile's and the Statistics page's switch
    static let profileKey = "profile.statsMedia"
}
