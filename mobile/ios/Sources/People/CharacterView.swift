import SwiftUI

/// A character's page (28): portrait, native name, role and favourites, the facts in columns, About with spoilers
/// hidden, who voices them, and every title they appear in with your status.
struct CharacterView: View {
    let id: String

    var body: some View {
        PageLoader(id: id, load: { try await $0.characterPage(id) }) { page in
            CharacterPageBody(page: page)
        }
        .pageBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CharacterPageBody: View {
    let page: CharacterPage

    @State private var favourite = false
    @State private var spoilers = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                head
                if !page.facts.isEmpty {
                    PeopleFactColumns(items: page.facts.map { (value: $0.value, label: $0.label) })
                        .padding(.top, 22)
                }
                about
                voices
                appearances
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .toolbar {
            PeopleToolbar(share: .character(page.id), name: page.name, favourite: $favourite)
        }
    }

    private var head: some View {
        PeopleHead(image: page.image, name: page.name, native: page.native) {
            if let h = page.headline { PeopleHeadLine(text: h) }
            if let f = page.favourites {
                HStack(spacing: 6) {
                    PeopleFavourites(count: f + (favourite ? 1 : 0)).foregroundStyle(Theme.inkSoft)
                    Text("favourites").foregroundStyle(Theme.inkMuted)
                }
                .font(.system(size: 14))
                .padding(.top, 6)
            }
        }
    }

    @ViewBuilder private var about: some View {
        let prose = page.prose
        if !prose.text.isEmpty || prose.hasSpoilers {
            VStack(alignment: .leading, spacing: 0) {
                PeopleSection("About")
                MoreText(text: spoilers ? prose.full : prose.text, lines: 3, size: 15)
                if prose.hasSpoilers && !spoilers {
                    Button {
                        spoilers = true
                    } label: {
                        Label("Show spoilers", systemImage: "eye")
                    }
                    .buttonStyle(.capsule(.tone, .small))
                    .padding(.horizontal, Theme.pad)
                    .padding(.top, 10)
                }
            }
            .padding(.top, 24)
        }
    }

    @ViewBuilder private var voices: some View {
        if !page.voices.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                PeopleSection("Voiced by")
                ForEach(page.voices) { v in VoiceRow(voice: v) }
            }
            .padding(.top, 22)
        }
    }

    @ViewBuilder private var appearances: some View {
        if !page.appearances.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PeopleSection(title: "Appears in") {
                    Text(Format.grouped(page.total)).numbers()
                }
                ForEach(Array(page.appearances.enumerated()), id: \.element.id) { i, a in
                    AppearanceRow(appearance: a, separator: i < page.appearances.count - 1)
                }
            }
            .padding(.top, 24)
        }
    }
}

/// Mayumi Tanaka · Japanese · 田中真弓 ›
private struct VoiceRow: View {
    let voice: CharacterPage.Voice

    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            if let id = voice.id { model.open(.person(id)) }
        } label: {
            HStack(spacing: 12) {
                Avatar(url: voice.image, size: 48)
                VStack(alignment: .leading, spacing: 1) {
                    Text(voice.name).font(.rowTitle).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(voice.line).font(.caption14).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 8)
                if voice.id != nil {
                    Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            .padding(.horizontal, Theme.pad)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(voice.id == nil)
    }
}

/// A title the character is in: cover, name, "TV · 1999 · Main", your status if it's on your list.
private struct AppearanceRow: View {
    let appearance: CharacterPage.Appearance
    var separator = true

    @Environment(AppModel.self) private var model

    var body: some View {
        let t = appearance.title
        let entry = model.entry(t.id)
        HStack(spacing: 14) {
            Poster(url: t.cover, width: 44, radius: 6, flat: true)
                .padding(.vertical, 8)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.name).font(.rowTitle).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(appearance.line).font(.caption14).foregroundStyle(Theme.inkMuted).lineLimit(1).numbers()
                }
                Spacer(minLength: 8)
                if let entry { PeopleStatusPill(entry: entry) }
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) { if separator { Hairline() } }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.pad)
        .contentShape(Rectangle())
        .onTapGesture { model.open(.title(t.id)) }
        .modifier(PeopleEntryMenu(entry: entry))
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open") { model.open(.title(t.id)) }
    }
}
