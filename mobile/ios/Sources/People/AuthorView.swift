import SwiftUI

/// An author's page (31): photo, what they write, born, the numbers in columns, About, then every book with your
/// status, how far you are, your score, or a Plan to Read button.
struct AuthorView: View {
    let id: String

    var body: some View {
        PageLoader(id: id, load: { try await $0.authorPage(id) }) { page in
            AuthorPageBody(page: page)
        }
        .pageBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AuthorPageBody: View {
    let page: AuthorPage

    @Environment(AppModel.self) private var model
    @State private var newestFirst = true
    @State private var favourite = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PeopleHead(image: page.photo, name: page.name, width: 108) {
                    PeopleHeadLine(text: page.headline)
                    if let born = page.bornLine { PeopleHeadLine(text: born, muted: true) }
                }
                PeopleFactColumns(items: facts).padding(.top, 22)
                about
                books
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .toolbar {
            PeopleToolbar(share: .author(page.id), name: page.name, favourite: $favourite)
        }
    }

    private var facts: [(value: String, label: String)] {
        // the answer has no page total: books shown, then everything Open Library lists when it says
        var out: [(value: String, label: String)] = [
            (value: Format.grouped(page.books.count), label: page.books.count == 1 ? "Book" : "Books"),
        ]
        if let w = page.works, w != page.books.count { out.append((value: Format.grouped(w), label: "Works")) }
        if let r = page.averageRating { out.append((value: "★ " + r, label: "Avg rating")) }
        out.append((value: Format.grouped(page.inLibrary(model.library)), label: "In your library"))
        return out
    }

    @ViewBuilder private var about: some View {
        let text = page.prose.text
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PeopleSection("About")
                MoreText(text: text, lines: 2, size: 15)
            }
            .padding(.top, 22)
        }
    }

    private var books: some View {
        let list = page.sorted(newestFirst: newestFirst)
        return VStack(alignment: .leading, spacing: 0) {
            PeopleSection(title: "Books") {
                Menu {
                    Picker("Order", selection: $newestFirst) {
                        Text("Newest first").tag(true)
                        Text("Oldest first").tag(false)
                    }
                } label: {
                    Text(newestFirst ? "Newest first" : "Oldest first")
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { i, b in
                BookRow(book: b, separator: i < list.count - 1)
            }
        }
        .padding(.top, 24)
    }
}

/// One book: cover, title, "2021 · 496 pages · ★ 4.5", then your status with your page or score, or Plan to Read.
private struct BookRow: View {
    let book: AuthorPage.Book
    var separator = true

    @Environment(AppModel.self) private var model

    var body: some View {
        let t = book.title
        let entry = model.entry(t.id)
        HStack(spacing: 14) {
            Poster(url: t.cover, width: 56, radius: 4)
                .padding(.vertical, 10)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.name).font(.rowTitle).foregroundStyle(Theme.ink).lineLimit(1)
                        info
                    }
                    Spacer(minLength: 8)
                    action(entry)
                }
                extra(entry)
            }
            .padding(.vertical, 12)
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

    private var info: some View {
        HStack(spacing: 6) {
            Text(book.line).numbers()
            if let r = book.rating {
                Text("·")
                ScoreLabel(value: Format.average(r), size: 14, muted: true)
            }
        }
        .font(.caption14)
        .foregroundStyle(Theme.inkMuted)
        .lineLimit(1)
    }

    @ViewBuilder private func action(_ entry: LibraryEntry?) -> some View {
        if let entry {
            PeopleStatusPill(entry: entry, chevron: false)
        } else {
            Button {
                model.change(book.id, LibraryPatch(status: .planned), title: book.title)
            } label: {
                Label("Plan to Read", systemImage: "plus")
            }
            .buttonStyle(.capsule(.tone, .small))
        }
    }

    @ViewBuilder private func extra(_ entry: LibraryEntry?) -> some View {
        if let entry, entry.status.isActive {
            HStack(spacing: 8) {
                ProgressBar(fraction: entry.fraction ?? 0)
                Text(AuthorPage.pageLine(entry)).font(.system(size: 12)).foregroundStyle(Theme.inkMuted).numbers()
            }
            .padding(.top, 8)
        } else if let entry, let s = entry.score10 {
            Text("Your score \(Text(s).foregroundStyle(Theme.ink).fontWeight(.semibold))")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .numbers()
                .padding(.top, 6)
        }
    }
}
