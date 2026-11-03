import SwiftUI

/// One season of a show (22): its episodes with a circle to mark each watched; the next one is highlighted. Marking
/// changes the show's one progress count on the list (episodes across the seasons).
struct SeasonView: View {
    let titleId: String
    let number: Int

    var body: some View {
        PageLoader(id: "\(titleId)/\(number)", load: { [titleId, number] in try await $0.tvSeason(titleId, number) }) { page in
            SeasonPageBody(page: page)
        }
        .pageBackground()
        .navigationTitle("Season \(number)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SeasonPageBody: View {
    let page: TVSeasonPage

    @Environment(AppModel.self) private var model

    private var progress: Int { model.entry(page.show.title.id)?.progress ?? 0 }

    var body: some View {
        let watched = TVProgress.watched(in: page.season, progress: progress, page.seasons)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SeasonHeader(page: page, watched: watched).padding(.bottom, 18)
                ForEach(page.episodes) { ep in
                    SeasonEpisodeRow(episode: ep, watched: ep.number <= watched, upNext: ep.number == watched + 1) {
                        mark(ep)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { change(TVProgress.markAll(season: page.season.number, page.seasons)) } label: {
                    Image(systemName: "checkmark.circle")
                }
                .accessibilityLabel("Mark all watched")
                .disabled(watched >= page.season.count)
                Menu {
                    Button { model.open(.title(page.show.title.id)) } label: { Label("Open \(page.show.title.name)", systemImage: "tv") }
                    Button { change(TVProgress.patch(TVProgress.offset(page.season.number, page.seasons), page.seasons)) } label: {
                        Label("Mark season unwatched", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(watched == 0)
                    if model.entry(page.show.title.id) != nil {
                        Button { model.sheet = .editor(page.show.title.id, expanded: false) } label: {
                            Label("Edit your list entry", systemImage: "slider.horizontal.3")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
    }

    private func mark(_ ep: Episode) {
        change(TVProgress.mark(episode: ep.number, season: page.season.number, progress: progress, page.seasons))
    }

    /// a progress change; a show not on the list yet is added as watching
    private func change(_ patch: LibraryPatch) {
        var patch = patch
        if let e = model.entry(page.show.title.id) {
            if e.status == .planned, patch.status == nil, (patch.progress ?? 0) > 0 { patch.status = .current }
            model.change(page.show.title.id, patch)
        } else {
            if patch.status == nil { patch.status = .current }
            model.change(page.show.title.id, patch, title: page.show.title)
        }
    }
}

/// poster, "Season 2", the show and year, how far you are
private struct SeasonHeader: View {
    let page: TVSeasonPage
    let watched: Int

    var body: some View {
        let s = page.season
        HStack(alignment: .center, spacing: 16) {
            Poster(url: s.poster ?? page.show.title.cover, width: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(s.name).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text([page.show.title.name, s.year.map { String($0) }, page.show.title.media.units(s.count)]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 14)).foregroundStyle(Theme.inkMuted).lineLimit(2)
                ProgressBar(fraction: Double(watched) / Double(max(1, s.count))).padding(.top, 8)
                Text("\(watched) of \(s.count) watched").font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                    .numbers().padding(.top, 2)
            }
        }
        .padding(.horizontal, Theme.pad)
    }
}

/// one episode: still, number and name, date and length, and its circle
private struct SeasonEpisodeRow: View {
    let episode: Episode
    let watched: Bool
    let upNext: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            still
            VStack(alignment: .leading, spacing: 3) {
                if upNext {
                    Text("Up next").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.brandSoft)
                }
                Text("\(episode.number)  \(episode.name)").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(watched ? Theme.inkSoft : Theme.ink).lineLimit(2)
                Text(episode.line).font(.system(size: 13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: toggle) { circle }
                .buttonStyle(.plain)
                .accessibilityLabel(watched ? "Mark episode \(episode.number) not watched"
                                            : "Mark episode \(episode.number) watched")
        }
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, 10)
        .background(upNext ? Theme.brand.opacity(0.07) : Color.clear)
    }

    private var still: some View {
        Artwork(url: episode.still)
            .frame(width: 116, height: 65)
            .overlay { if watched { Color.black.opacity(0.45) } }
            .overlay(alignment: .bottom) {
                if watched { ProgressBar(fraction: 1, color: .white).padding(6) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder private var circle: some View {
        if watched {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 26))
                .foregroundStyle(.white, Theme.color(.current))
        } else {
            Circle().strokeBorder(upNext ? Theme.brand : Theme.inkFaint, lineWidth: upNext ? 2 : 1.5)
                .frame(width: 26, height: 26)
        }
    }
}
