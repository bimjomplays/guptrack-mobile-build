import SwiftUI

/// Statistics (43, 43b): one media at a time, all from the offline library. Time spent, the plain columns, the
/// score histogram, formats, release years, then genres and studios with how many titles and your mean score.
struct StatsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(MediaKind.profileKey) private var mediaRaw = MediaKind.anime.rawValue
    @State private var allGenres = false
    @State private var allStudios = false

    private var media: Binding<MediaKind> {
        Binding(get: { MediaKind(rawValue: mediaRaw) ?? .anime }, set: { mediaRaw = $0.rawValue })
    }

    var body: some View {
        let stats = LibraryStats(model.library, media: media.wrappedValue)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ProfileMediaPicker(media: media)
                if stats.summary.entries == 0 {
                    ContentUnavailableView("No \(media.wrappedValue.plural.lowercased()) yet",
                                           systemImage: media.wrappedValue.symbol,
                                           description: Text("Titles you add show up here."))
                        .padding(.top, 60)
                } else {
                    StatsHeadline(stats: stats)
                    sections(stats)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .pageBackground()
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: stats.shareText(name: model.account?.user.name ?? "My")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share statistics")
            }
        }
    }

    @ViewBuilder
    private func sections(_ stats: LibraryStats) -> some View {
        SectionHeader(title: "Scores", chevron: false) {
            Text("\(Format.grouped(stats.summary.scored)) scored").font(.system(size: 14))
                .foregroundStyle(Theme.inkMuted).numbers()
        }
        .sectionGap(18)
        StatsBars(values: stats.histogram, labels: (1...10).map(String.init), height: 92, maxBar: 64, spacing: 6,
                  color: Theme.brand, emptyAsTrack: true)
        if !stats.formats.isEmpty {
            SectionHeader("Formats", chevron: false).sectionGap(20)
            FormatsBar(formats: stats.formats)
        }
        if !stats.years.isEmpty {
            SectionHeader("Release years", chevron: false).sectionGap(20)
            StatsBars(values: stats.years.map(\.count), labels: stats.years.map(\.label), height: 80, maxBar: 56,
                      spacing: 10, color: Theme.brand.opacity(0.7), emptyAsTrack: false)
        }
        if !stats.genres.isEmpty {
            SectionHeader(title: "Genres", chevron: false) {
                if stats.genres.count > 7 {
                    Button { allGenres.toggle() } label: { ProfileSeeAll(text: allGenres ? "Less" : "See all") }
                        .buttonStyle(.plain)
                }
            }
            .sectionGap(26)
            GroupBars(groups: Array(stats.genres.prefix(allGenres ? 50 : 7)), top: stats.genres[0].count)
        }
        if !stats.studios.isEmpty {
            SectionHeader(title: stats.peopleLabel, chevron: false) {
                if stats.studios.count > 6 {
                    Button { allStudios.toggle() } label: { ProfileSeeAll(text: allStudios ? "Less" : "See all") }
                        .buttonStyle(.plain)
                }
            }
            .sectionGap(24)
            GroupBars(groups: Array(stats.studios.prefix(allStudios ? 50 : 6)), top: stats.studios[0].count)
        }
    }
}

/// "Time watched / 20 days 4 hours / 1,234 episodes · …" and the columns under it, a hairline below
private struct StatsHeadline: View {
    let stats: LibraryStats

    var body: some View {
        let s = stats.summary
        let head = s.timeHeadline
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.timeLabel).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(head.main).foregroundStyle(Theme.ink)
                    Text(head.rest).foregroundStyle(Theme.inkSoft)
                }
                .font(.system(size: 34, weight: .bold))
                .numbers()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Text(s.timeLine).font(.system(size: 14)).foregroundStyle(Theme.inkMuted).numbers()
            }
            .padding(.top, 16)
            HStack(alignment: .top, spacing: 10) {
                StatColumn(value: s.meanText, label: "Mean score")
                StatColumn(value: stats.medianText, label: "Median")
                StatColumn(value: Format.grouped(stats.perfect), label: "Perfect 10s")
                StatColumn(value: Format.grouped(s.rewatched), label: s.media.isReading ? "Reread" : "Rewatched")
            }
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, Theme.pad)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// a row of simple bars with the number over each and a label under it (scores, release years)
private struct StatsBars: View {
    let values: [Int]
    let labels: [String]
    var height: CGFloat
    var maxBar: CGFloat
    var spacing: CGFloat
    var color: Color
    var emptyAsTrack: Bool

    var body: some View {
        let top = max(1, values.max() ?? 1)
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, n in
                    VStack(spacing: 5) {
                        Text(n > 0 ? Format.grouped(n) : " ").font(.system(size: 11)).foregroundStyle(Theme.inkMuted)
                            .numbers()
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(n > 0 || !emptyAsTrack ? color : Theme.track)
                            .frame(height: n > 0 ? max(4, CGFloat(n) / CGFloat(top) * maxBar) : (emptyAsTrack ? 3 : 4))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(height: height)
            HStack(spacing: spacing) {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, l in
                    Text(l).font(.system(size: 12)).foregroundStyle(Theme.inkMuted).numbers()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, Theme.pad)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(zip(labels, values).map { "\($0): \($1)" }.joined(separator: ", "))
    }
}

/// the formats as one bar of coloured parts and a legend
private struct FormatsBar: View {
    let formats: [LibraryStats.Slice]

    var body: some View {
        let total = max(1, formats.reduce(0) { $0 + $1.count })
        VStack(alignment: .leading, spacing: 11) {
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(formats) { f in
                        Color(hex: f.color)
                            .frame(width: max(3, (g.size.width - CGFloat(formats.count - 1) * 2) * CGFloat(f.count) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())
            .accessibilityHidden(true)
            ProfileFlow(spacing: 16, lineSpacing: 6) {
                ForEach(formats) { f in
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: f.color)).frame(width: 8, height: 8)
                        Text(f.label).foregroundStyle(Theme.inkMuted)
                        Text(Format.grouped(f.count)).fontWeight(.semibold).foregroundStyle(Theme.ink)
                    }
                    .font(.system(size: 13))
                    .numbers()
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.horizontal, Theme.pad)
    }
}

/// genres or studios: name, "12 titles", your mean score, a thin bar; hairlines between
private struct GroupBars: View {
    let groups: [LibraryStats.Group]
    let top: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                VStack(spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(g.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(ProfileText.count(g.count, "title")).font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                            .numbers()
                        HStack {
                            Spacer(minLength: 0)
                            if let m = g.meanText { ScoreLabel(value: m, size: 13) }
                        }
                        .frame(width: 46)
                    }
                    ProgressBar(fraction: Double(g.count) / Double(max(1, top)), color: Theme.brand, height: 4)
                }
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) { if i < groups.count - 1 { Hairline() } }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, Theme.pad)
    }
}
