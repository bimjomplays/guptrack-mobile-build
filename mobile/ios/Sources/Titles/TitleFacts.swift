import SwiftUI

/// Seasons (21): each season's poster, year and size, with a check when watched or how far you are.
struct TitleSeasons: View {
    let page: TitlePage
    let seasons: [TVSeason]

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleHeading("Seasons", count: seasons.count)
            ForEach(seasons) { s in
                Button { model.open(.season(page.title.id, s.number)) } label: { row(s) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func row(_ s: TVSeason) -> some View {
        let progress = model.entry(page.title.id)?.progress
        let watched = progress.map { TVProgress.watched(in: s, progress: $0, seasons) } ?? 0
        return HStack(spacing: 12) {
            Poster(url: s.poster ?? page.title.cover, width: 44, radius: 7, flat: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.name).font(.rowTitle).foregroundStyle(Theme.ink)
                Text([s.year.map { String($0) }, page.title.media.units(s.count)].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 8)
            if watched >= s.count {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20))
                    .foregroundStyle(Theme.color(.current))
                    .accessibilityLabel("Watched")
            } else if watched > 0 {
                VStack(alignment: .trailing, spacing: 5) {
                    ProgressBar(fraction: Double(watched) / Double(max(1, s.count))).frame(width: 64)
                    Text("\(watched) of \(s.count)").font(.system(size: 12)).foregroundStyle(Theme.inkMuted).numbers()
                }
            }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkFaint)
        }
        .frame(height: 78)
        .padding(.horizontal, Theme.pad)
        .contentShape(Rectangle())
    }
}

/// The score average (17): the number, how many have it, and how the scores spread.
struct TitleScoreAverage: View {
    let page: TitlePage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleHeading("Score")
            HStack(alignment: .bottom, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(page.averageText ?? "–").font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.ink).numbers()
                    Text(page.title.media == .book ? "out of 5" : "out of 10")
                        .font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                }
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(page.scoreHeights, id: \.score) { bar in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(bar.score >= 70 ? Theme.brand : Color.gray.opacity(0.45))
                            .frame(height: max(3, 58 * bar.height))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 58, alignment: .bottom)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.pad)
            if let members = page.membersLine {
                Text(members).font(.system(size: 13)).foregroundStyle(Theme.inkMuted).numbers()
                    .padding(.horizontal, Theme.pad).padding(.top, 8)
            }
        }
    }
}

/// Details (17, 23b): the facts, studios and authors as links, and your history with a film.
struct TitleDetails: View {
    let page: TitlePage

    @Environment(AppModel.self) private var model

    var body: some View {
        let rows = page.details
        let entry = page.title.media == .movie ? model.entry(page.title.id) : nil
        VStack(alignment: .leading, spacing: 0) {
            TitleHeading("Details")
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, d in
                    row(d, last: i == rows.count - 1 && entry == nil)
                }
                if let entry { history(entry) }
            }
            .padding(.horizontal, Theme.pad)
        }
    }

    private func row(_ d: TitlePage.Detail, last: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(d.label).foregroundStyle(Theme.inkMuted).frame(width: 118, alignment: .leading)
            if let route = d.ref.flatMap(TitlePage.route(for:)) {
                Button(d.value) { model.open(route) }
                    .buttonStyle(.plain).foregroundStyle(Theme.brandSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(d.value).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 15))
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { if !last { Hairline() } }
    }

    private func history(_ e: LibraryEntry) -> some View {
        let rest = TitleListText.history(e)
        return HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("Your history").foregroundStyle(Theme.inkMuted).frame(width: 118, alignment: .leading)
            (Text(e.status.label(e.media)).foregroundStyle(Theme.color(e.status))
             + Text(rest.isEmpty ? "" : " · " + rest).foregroundStyle(Theme.ink))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 15))
        .padding(.vertical, 11)
    }
}

/// Reviews: a row to the title's reviews.
struct TitleReviewsRow: View {
    let page: TitlePage

    @Environment(AppModel.self) private var model

    var body: some View {
        Button { model.open(.reviews(page.title.id)) } label: {
            PlainRow("Reviews", value: page.reviews.map { Format.grouped($0) }, symbol: "text.bubble",
                     symbolColor: Theme.brand)
        }
        .buttonStyle(.plain)
    }
}

/// More like this: recommendations as poster cards with their average.
struct TitleMoreLikeThis: View {
    let titles: [Title]

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleHeading("More like this")
            Shelf(spacing: 12) {
                ForEach(titles) { t in
                    Button { model.open(.title(t.id)) } label: {
                        PosterCard(url: t.cover, title: t.name, width: 104) {
                            if let s = t.score { ScoreLabel(value: Format.average(s), muted: true) } else { Text(t.media.singular) }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { if let e = model.entry(t.id) { EntryMenu(entry: e) } }
                }
            }
        }
    }
}
