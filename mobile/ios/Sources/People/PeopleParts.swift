import SwiftUI

// Parts the four people pages (28-31) share: the portrait head, the fact columns, the section titles and the
// favourites count. Drawn from design/iphone/screens/_browse.mjs (personHead, factCols, secTitle, favs).

/// Portrait + name block: the picture on the left, the name and lines bottom-aligned beside it.
struct PeopleHead<Lines: View>: View {
    let image: URL?
    let name: String
    var native: String?
    var width: CGFloat = 116
    var ratio: CGFloat = 1.42
    @ViewBuilder var lines: () -> Lines

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            portrait
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                if let native, !native.isEmpty {
                    Text(native).font(.system(size: 14)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        .padding(.top, 3)
                }
                lines()
            }
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.pad)
    }

    private var portrait: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Artwork(url: image)
            .frame(width: width, height: (width * ratio).rounded())
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.keyline, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 11, y: 8)
    }
}

/// one 14pt line under the name (soft ink; `muted` for the quieter "Born …" line)
struct PeopleHeadLine: View {
    let text: String
    var muted = false

    var body: some View {
        Text(text).font(.system(size: 14)).foregroundStyle(muted ? Theme.inkMuted : Theme.inkSoft).lineLimit(1)
            .padding(.top, 6)
    }
}

/// ♥ 35,992
struct PeopleFavourites: View {
    let count: Int
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill").font(.system(size: size - 1)).foregroundStyle(Color(hex: 0xFF6482))
            Text(Format.grouped(count)).numbers()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Format.grouped(count)) favourites")
    }
}

/// Facts in plain columns, value over label, a hairline between them (never tiles).
struct PeopleFactColumns: View {
    let items: [(value: String, label: String)]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.value).font(.system(size: 17, weight: .semibold)).tracking(-0.3)
                        .foregroundStyle(Theme.ink).numbers().lineLimit(1).minimumScaleFactor(0.8)
                    Text(item.label).font(.system(size: 12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                .padding(.leading, i == 0 ? 0 : 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    if i > 0 { Rectangle().fill(Theme.sep).frame(width: 0.5) }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, Theme.pad)
    }
}

/// The people pages' 20pt section title, with something quiet on the right.
struct PeopleSection<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 20, weight: .bold)).tracking(-0.5).foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing().font(.system(size: 15)).foregroundStyle(Theme.inkMuted)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.bottom, 8)
    }
}

extension PeopleSection where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title, trailing: { EmptyView() })
    }
}

/// The status pill on a row: a menu of statuses for a title on your list.
struct PeopleStatusPill: View {
    let entry: LibraryEntry
    var chevron = true

    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Picker("Status", selection: Binding(get: { entry.status },
                                                set: { model.change(entry.id, LibraryPatch(status: $0)) })) {
                ForEach(ListStatus.ordered) { s in Text(s.label(entry.media)).tag(s) }
            }
        } label: {
            StatusPillLabel(status: entry.status, media: entry.media, small: true, chevron: chevron)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Status: \(entry.status.label(entry.media))")
    }
}

/// a coloured dot and the status's words, for a card's caption
struct PeopleStatusCaption: View {
    let entry: LibraryEntry

    var body: some View {
        HStack(spacing: 5) {
            StatusDot(status: entry.status, size: 7)
            Text(entry.status.label(entry.media)).fontWeight(.medium).foregroundStyle(Theme.inkSoft)
        }
    }
}

/// The ♥ and share buttons in the top bar (Liquid Glass comes with the toolbar).
struct PeopleToolbar: ToolbarContent {
    let share: Route
    let name: String
    var favourite: Binding<Bool>?
    var more: (() -> Void)?

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let favourite {
                Button {
                    favourite.wrappedValue.toggle()
                } label: {
                    Image(systemName: favourite.wrappedValue ? "heart.fill" : "heart")
                }
                .accessibilityLabel(favourite.wrappedValue ? "Remove from favourites" : "Add to favourites")
            }
            ShareLink(item: share.url, subject: Text(name)) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share")
            if let more {
                Button(action: more) {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
    }
}

/// the title's long-press menu, only when it's on your list
struct PeopleEntryMenu: ViewModifier {
    let entry: LibraryEntry?

    @ViewBuilder func body(content: Content) -> some View {
        if let entry {
            content.contextMenu { EntryMenu(entry: entry) }
        } else {
            content
        }
    }
}
