import SwiftUI

/// Characters & voices (17): the character's art, name, and the voice under it (Japanese first).
struct TitleCharacters: View {
    let characters: [CharacterCredit]

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleHeading("Characters & voices", count: characters.count)
            Shelf(spacing: 12) {
                ForEach(characters, id: \.self) { c in
                    Button { if let r = c.character.route { model.open(r) } } label: { card(c) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func card(_ c: CharacterCredit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Artwork(url: c.character.image).frame(width: 92, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(c.character.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                .lineLimit(2).multilineTextAlignment(.leading).padding(.top, 7)
            if let v = c.voice {
                Text(v.person.name).font(.system(size: 12)).foregroundStyle(Theme.inkMuted).lineLimit(1).padding(.top, 1)
            }
        }
        .frame(width: 92, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Cast (23b): round portraits with the name and the part.
struct TitleCast: View {
    let cast: [Credit]

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleHeading("Cast", count: cast.count)
            Shelf(spacing: 14) {
                ForEach(cast, id: \.self) { c in
                    Button { if let r = c.person.route { model.open(r) } } label: { card(c) }
                        .buttonStyle(.plain)
                        .disabled(c.person.route == nil)
                }
            }
        }
    }

    private func card(_ c: Credit) -> some View {
        VStack(spacing: 0) {
            Artwork(url: c.person.image).frame(width: 84, height: 84).clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.keyline, lineWidth: 0.5))
            Text(c.person.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                .lineLimit(2).multilineTextAlignment(.center).padding(.top, 8)
            if !c.role.isEmpty {
                Text(c.role).font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                    .lineLimit(2).multilineTextAlignment(.center).padding(.top, 1)
            }
        }
        .frame(width: 84)
        .accessibilityElement(children: .combine)
    }
}

/// Staff (anime) and crew (TV, films) (17, 23b): name on the left, the job on the right.
struct TitleCrew: View {
    let crew: [Credit]
    var heading = "Crew"

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleHeading(heading)
            VStack(spacing: 0) {
                ForEach(Array(crew.enumerated()), id: \.offset) { i, c in
                    Button { if let r = c.person.route { model.open(r) } } label: { row(c, last: i == crew.count - 1) }
                        .buttonStyle(.plain)
                        .disabled(c.person.route == nil)
                }
            }
            .padding(.horizontal, Theme.pad)
        }
    }

    private func row(_ c: Credit, last: Bool) -> some View {
        HStack(spacing: 10) {
            Text(c.person.name).font(.rowTitle).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: 8)
            if !c.role.isEmpty {
                Text(c.role).font(.system(size: 15)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            if c.person.route != nil {
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
    let relations: [TitleDetail.Relation]

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleHeading("Related")
            ForEach(relations, id: \.self) { r in
                let t = r.title.app
                Button { model.open(.title(t.id)) } label: { row(r, t) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func row(_ r: TitleDetail.Relation, _ t: Title) -> some View {
        HStack(spacing: 12) {
            Poster(url: t.cover, width: 44, ratio: 64.0 / 44.0, radius: 6, flat: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.relationLabel(r)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                Text(t.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                status(t)
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
