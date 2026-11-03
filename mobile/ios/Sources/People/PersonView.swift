import SwiftUI
import UIKit

/// A person's page (29): an actor (photo, bio, Known for with your status, the filmography by year with their
/// part), a voice actor (Roles: the characters they voice) or a staff member. AniList staff and TMDB people alike.
struct PersonView: View {
    let id: String

    var body: some View {
        PageLoader(id: id, load: { try await $0.personPage(id) }) { page in
            PersonPageBody(page: page)
        }
        .pageBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PersonPageBody: View {
    let page: PersonPage

    @State private var group: String?
    @State private var kind: MediaKind = .movie

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                head
                bio
                knownFor
                credits
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .toolbar { toolbar }
    }

    private var head: some View {
        PeopleHead(image: page.image, name: page.name, native: page.native, width: 100) {
            if let h = page.headline { PeopleHeadLine(text: h) }
            if let born = page.bornLine { PeopleHeadLine(text: born, muted: true) }
        }
    }

    @ViewBuilder private var bio: some View {
        let text = page.prose.text
        if !text.isEmpty {
            MoreText(text: text, lines: 2, size: 15)
                .padding(.top, 16)
        }
    }

    @ViewBuilder private var knownFor: some View {
        if !page.knownFor.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PeopleSection("Known for")
                Shelf(spacing: 12) {
                    ForEach(page.knownFor) { t in KnownForCard(title: t) }
                }
            }
            .padding(.top, 20)
        }
    }

    private var credits: some View {
        let groups = page.groups
        let chosen = group ?? groups.first
        let all = page.credits(groups.count > 1 ? chosen : nil)
        // an actor's or director's films and shows split into Movies and TV (anime and books keep their groups)
        let films = groups.count == 1 && !all.isEmpty && all.allSatisfy { $0.title.media == .movie || $0.title.media == .tv }
        let movies = all.filter { $0.title.media == .movie }, shows = all.filter { $0.title.media == .tv }
        let both = films && !movies.isEmpty && !shows.isEmpty
        let list = both ? (kind == .tv ? shows : movies) : all
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(films ? "Filmography" : groups.count == 1 ? groups[0] : "Credits")
                    .font(.system(size: 20, weight: .bold)).tracking(-0.5)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                if both {
                    Picker("Filmography", selection: $kind) {
                        Text("Movies \(movies.count)").tag(MediaKind.movie)
                        Text("TV \(shows.count)").tag(MediaKind.tv)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                } else if groups.count > 1 {
                    Picker("Credits", selection: Binding(get: { chosen ?? "" }, set: { group = $0 })) {
                        ForEach(groups, id: \.self) { g in Text(g).tag(g) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                } else {
                    Text(Format.grouped(list.count)).font(.system(size: 15)).foregroundStyle(Theme.inkMuted).numbers()
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.bottom, 2)
            ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                CreditRow(credit: c, separator: i < list.count - 1)
            }
        }
        .padding(.top, 22)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            ShareLink(item: Route.person(page.id).url, subject: Text(page.name)) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share")
            Menu {
                Button {
                    UIPasteboard.general.string = page.name
                } label: {
                    Label("Copy name", systemImage: "doc.on.doc")
                }
                Button {
                    UIPasteboard.general.url = Route.person(page.id).url
                } label: {
                    Label("Copy link", systemImage: "link")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("More")
        }
    }
}

/// A Known for poster: the title, then your status if it's on your list, else its year.
private struct KnownForCard: View {
    let title: Title

    @Environment(AppModel.self) private var model

    var body: some View {
        let entry = model.entry(title.id)
        NavigationLink(value: Route.title(title.id)) {
            VStack(alignment: .leading, spacing: 0) {
                Poster(url: title.cover, width: 88, radius: 9)
                Text(title.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                    .lineLimit(1).padding(.top, 7)
                Group {
                    if let entry {
                        PeopleStatusCaption(entry: entry)
                    } else {
                        Text(title.year.map(String.init) ?? "").numbers()
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .lineLimit(1)
                .padding(.top, 1)
            }
            .frame(width: 88, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .modifier(PeopleEntryMenu(entry: entry))
    }
}

/// 2024 · poster · Dune: Part Two / as Paul Atreides · your status (or the score). A voice role shows the
/// character instead, and opens the character.
private struct CreditRow: View {
    let credit: PersonPage.Credit
    var separator = true

    @Environment(AppModel.self) private var model

    var body: some View {
        let t = credit.title
        let entry = model.entry(t.id)
        HStack(alignment: .center, spacing: 14) {
            Text(credit.year.map(String.init) ?? "TBA")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.inkMuted).numbers()
                .frame(width: 40, alignment: .leading)
            Poster(url: credit.character?.image ?? t.cover, width: 40, radius: 5, flat: true)
                .padding(.vertical, 8)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(credit.character?.name ?? t.name).font(.rowTitle).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(credit.line).font(.caption14).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 8)
                trailing(entry)
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) { if separator { Hairline() } }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.pad)
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .modifier(PeopleEntryMenu(entry: entry))
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open") { open() }
    }

    @ViewBuilder private func trailing(_ entry: LibraryEntry?) -> some View {
        if let entry {
            PeopleStatusPill(entry: entry, chevron: false)
        } else if let s = credit.title.score {
            ScoreLabel(value: Format.average(s), size: 14, muted: true)
        }
    }

    private func open() {
        model.open(credit.route)
    }
}
