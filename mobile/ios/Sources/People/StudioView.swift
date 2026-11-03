import SwiftUI

/// A studio's page (30): the name, what it is and where, favourites, how many titles (and how many are on your
/// list), a format filter, then the titles in a grid by year with your status where it's on your list. TV networks
/// and film companies (HBO, A24) use the same page.
struct StudioView: View {
    let id: String

    var body: some View {
        PageLoader(id: id, load: { try await $0.studioPage(id) }) { page in
            StudioPageBody(page: page)
        }
        .pageBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StudioPageBody: View {
    let page: StudioPage

    @Environment(AppModel.self) private var model
    @State private var filter: StudioPage.Filter = .all
    @State private var favourite = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                head
                filters
                ForEach(page.years(filter)) { g in YearSection(group: g) }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .toolbar {
            PeopleToolbar(share: .studio(page.id), name: page.name,
                          favourite: page.favourites == nil ? nil : $favourite)
        }
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(page.name).font(.system(size: 34, weight: .bold)).tracking(-1.2).foregroundStyle(Theme.ink)
                .lineLimit(2).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            if !page.headline.isEmpty {
                Text(page.headline).font(.system(size: 15)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    .padding(.top, 4)
            }
            HStack(spacing: 8) {
                if let f = page.favourites {
                    PeopleFavourites(count: f + (favourite ? 1 : 0), size: 15)
                    Text("·")
                }
                Text(page.countLine(inLibrary: page.inLibrary(model.library))).numbers()
            }
            .font(.system(size: 15))
            .foregroundStyle(Theme.inkMuted)
            .lineLimit(1)
            .padding(.top, 4)
        }
        .padding(.horizontal, Theme.pad)
    }

    @ViewBuilder private var filters: some View {
        let list = page.filters
        if !list.isEmpty {
            Picker("Format", selection: $filter) {
                ForEach(list) { f in Text(f.label).tag(f) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.pad)
            .padding(.top, 16)
        }
    }
}

/// "2026  4" and that year's titles, four to a row.
private struct YearSection: View {
    let group: StudioPage.YearGroup

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.label).font(.system(size: 20, weight: .bold)).tracking(-0.5).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(Format.grouped(group.titles.count)).font(.system(size: 15)).foregroundStyle(Theme.inkMuted)
            }
            .numbers()
            .padding(.horizontal, Theme.pad)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(group.titles) { t in StudioCard(title: t) }
            }
            .padding(.horizontal, Theme.pad)
        }
        .padding(.top, 22)
    }
}

/// A grid card: the poster (as wide as its column), two lines of title, the format, then your status or the score.
private struct StudioCard: View {
    let title: Title

    @Environment(AppModel.self) private var model

    var body: some View {
        let entry = model.entry(title.id)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        NavigationLink(value: Route.title(title.id)) {
            VStack(alignment: .leading, spacing: 0) {
                Artwork(url: title.cover)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Theme.keyline, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                Text(title.name).font(.cardTitle).foregroundStyle(Theme.ink).lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 8)
                Text(PeopleCaption.format(title)).font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                    .lineLimit(1).padding(.top, 1)
                caption(entry).font(.cardCaption).foregroundStyle(Theme.inkMuted).lineLimit(1).padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .modifier(PeopleEntryMenu(entry: entry))
    }

    @ViewBuilder private func caption(_ entry: LibraryEntry?) -> some View {
        if let entry {
            PeopleStatusCaption(entry: entry)
        } else if let s = title.score {
            ScoreLabel(value: Format.average(s), muted: true)
        } else {
            Text(" ")
        }
    }
}
