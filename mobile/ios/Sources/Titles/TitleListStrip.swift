import SwiftUI

/// "Your list" under the hero (16, 21, 23, 24, 25): status, progress, score and favourite, straight on the library.
/// Tapping the header opens the list editor. A title not on the list offers Add instead.
struct TitleListStrip: View {
    let page: TitlePage

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            Group {
                if let e = model.entry(page.title.id) {
                    TitleListControls(page: page, entry: e)
                } else {
                    TitleNotListed(title: page.title)
                }
            }
            .padding(.vertical, 13)
            Hairline()
        }
        .padding(.horizontal, Theme.pad)
    }
}

private struct TitleListControls: View {
    let page: TitlePage
    let entry: LibraryEntry

    @Environment(AppModel.self) private var model

    private var id: String { entry.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // the label stays its own text (so "Your list · Season 2" is read out); Edit is the button
            HStack {
                Text(TitleListText.label(entry, seasons: page.seasons))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .onTapGesture { model.sheet = .editor(id, expanded: false) }
                Spacer()
                Button { model.sheet = .editor(id, expanded: false) } label: {
                    HStack(spacing: 3) {
                        Text("Edit")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.brandSoft)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit your list entry")
            }
            .padding(.bottom, 10)
            HStack(spacing: 8) {
                StatusPill(status: entry.status, media: entry.media) { s in
                    model.change(id, LibraryPatch(status: s))
                }
                stepper
                Spacer(minLength: 0)
                TitleScoreButton(entry: entry)
                TitleCircleButton(symbol: entry.favourite ? "heart.fill" : "heart",
                                  label: entry.favourite ? "Remove from favourites" : "Add to favourites",
                                  size: 34, tint: entry.favourite ? Color(hex: 0xFF375F) : Theme.inkSoft) {
                    model.change(id, LibraryPatch(favourite: !entry.favourite))
                }
            }
            if let caption = TitleListText.caption(entry) {
                Text(caption).font(.system(size: 13)).foregroundStyle(Theme.inkMuted).numbers().padding(.top, 9)
            }
        }
    }

    @ViewBuilder private var stepper: some View {
        let seasons = page.seasons
        if entry.media == .tv, let pos = TVProgress.position(entry.progress, seasons) {
            ProgressStepper(progress: pos.watched, total: pos.count) {
                model.change(id, TVProgress.step(entry.progress, by: -1, seasons))
            } plus: {
                model.change(id, TVProgress.step(entry.progress, by: 1, seasons))
            }
        } else if entry.media.unit != nil {
            ProgressStepper(progress: entry.progress, total: entry.title.total ?? page.title.total) {
                model.step(id, by: -1)
            } plus: {
                model.step(id)
            }
        }
    }
}

/// ★ 9 when scored, a star circle when not; both open the editor
private struct TitleScoreButton: View {
    let entry: LibraryEntry

    @Environment(AppModel.self) private var model

    var body: some View {
        if let s = entry.score10 {
            Button { model.sheet = .editor(entry.id, expanded: false) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(Theme.star)
                    Text(s).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink).numbers()
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Theme.fill, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your score: \(s)")
        } else {
            TitleCircleButton(symbol: "star", label: "Score it", size: 34, tint: Theme.inkSoft) {
                model.sheet = .editor(entry.id, expanded: false)
            }
        }
    }
}

/// a title that isn't on the list yet
private struct TitleNotListed: View {
    let title: Title

    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Not in your list").font(.rowTitle).foregroundStyle(Theme.ink)
                Text(TitleListText.addLine(title.media)).font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 8)
            Button {
                model.change(title.id, LibraryPatch(status: .planned), title: title)
            } label: {
                Label("Add to List", systemImage: "plus")
            }
            .buttonStyle(.capsule(.tint, .small))
        }
    }
}
