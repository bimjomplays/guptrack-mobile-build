import SwiftUI

/// Characters & voices (17): the character's art, name, and the voice under it.
struct TitleCharacters: View {
    let characters: [TitlePage.Character]

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleHeading("Characters & voices", count: characters.count)
            Shelf(spacing: 12) {
                ForEach(characters, id: \.self) { c in
                    Button { if let r = c.route { model.open(r) } } label: { card(c) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func card(_ c: TitlePage.Character) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Artwork(url: c.image).frame(width: 92, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(c.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                .lineLimit(2).multilineTextAlignment(.leading).padding(.top, 7)
            if let v = c.voice {
                Text(v.name).font(.system(size: 12)).foregroundStyle(Theme.inkMuted).lineLimit(1).padding(.top, 1)
            }
        }
        .frame(width: 92, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Cast (23b): round portraits with the name and the part.
struct TitleCast: View {
    let cast: [TitlePage.Credit]

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleHeading("Cast", count: cast.count)
            Shelf(spacing: 14) {
                ForEach(cast, id: \.self) { p in
                    Button { if let r = p.route { model.open(r) } } label: { card(p) }
                        .buttonStyle(.plain)
                        .disabled(p.route == nil)
                }
            }
        }
    }

    private func card(_ p: TitlePage.Credit) -> some View {
        VStack(spacing: 0) {
            Artwork(url: p.image).frame(width: 84, height: 84).clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.keyline, lineWidth: 0.5))
            Text(p.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                .lineLimit(2).multilineTextAlignment(.center).padding(.top, 8)
            if let role = p.role {
                Text(role).font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                    .lineLimit(2).multilineTextAlignment(.center).padding(.top, 1)
            }
        }
        .frame(width: 84)
        .accessibilityElement(children: .combine)
    }
}

/// Crew and staff (17, 23b): name on the left, the job on the right.
struct TitleCrew: View {
    let crew: [TitlePage.Credit]

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleHeading(crew.contains { $0.ref?.hasPrefix("person:tmdb") == false } ? "Staff" : "Crew")
            VStack(spacing: 0) {
                ForEach(Array(crew.enumerated()), id: \.offset) { i, p in
                    Button { if let r = p.route { model.open(r) } } label: { row(p, last: i == crew.count - 1) }
                        .buttonStyle(.plain)
                        .disabled(p.route == nil)
                }
            }
            .padding(.horizontal, Theme.pad)
        }
    }

    private func row(_ p: TitlePage.Credit, last: Bool) -> some View {
        HStack(spacing: 10) {
            Text(p.name).font(.rowTitle).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: 8)
            if let job = p.role {
                Text(job).font(.system(size: 15)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            if p.route != nil {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkFaint)
            }
        }
        .frame(minHeight: 46)
        .overlay(alignment: .bottom) { if !last { Hairline() } }
        .contentShape(Rectangle())
    }
}

/// Related (17): prequels, sequels, the source, with where each is on your list.
struct TitleRelated: View {
    let page: TitlePage
    let relations: [TitlePage.Relation]

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleHeading("Related")
            ForEach(relations, id: \.self) { r in
                Button { model.open(.title(r.title.id)) } label: { row(r) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func row(_ r: TitlePage.Relation) -> some View {
        HStack(spacing: 12) {
            Poster(url: r.title.cover, width: 44, ratio: 64.0 / 44.0, radius: 6, flat: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.relationLabel(r)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                Text(r.title.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                status(r.title)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkFaint)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func status(_ t: Title) -> some View {
        let e = model.entry(t.id)
        return (Text(TitlePage.relationLine(t) + " · ").foregroundStyle(Theme.inkMuted)
                + Text(e.map { $0.status.label($0.media) } ?? "Not in your list")
                    .foregroundStyle(e.map { Theme.color($0.status) } ?? Theme.inkMuted))
            .font(.system(size: 13)).lineLimit(1)
    }
}
