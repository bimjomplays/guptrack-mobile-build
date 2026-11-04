import SwiftUI

/// What a long press on a title on your list offers (07), everywhere a title shows: +1 with what it changes, status,
/// rating, Open in Harbor, a custom list, send, share, drop. Use it as `.contextMenu { EntryMenu(entry: e) }`.
struct EntryMenu: View {
    let entry: LibraryEntry

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        let media = entry.media
        Section {
            if let unit = media.unit, entry.left.map({ $0 > 0 }) ?? true {
                let next = entry.progress + media.step
                Button {
                    model.step(entry.id)
                } label: {
                    Label {
                        Text(media == .book ? "Read 10 more pages" : "\(media.isReading ? "Read" : "Watched") \(unit) \(Format.grouped(next))")
                        Text(entry.title.total.map { "\(Format.grouped(entry.progress)) of \(Format.grouped($0)) → \(Format.grouped(min(next, $0))) of \(Format.grouped($0))" }
                            ?? "\(Format.grouped(entry.progress)) → \(Format.grouped(next))")
                    } icon: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
            Menu {
                Picker("Status", selection: Binding(get: { entry.status },
                                                    set: { model.change(entry.id, LibraryPatch(status: $0)) })) {
                    ForEach(ListStatus.ordered) { s in Text(s.label(media)).tag(s) }
                }
            } label: {
                Label("Set status", systemImage: "circle.dashed")
            }
            Menu {
                Picker("Score", selection: Binding(get: { entry.score ?? 0 },
                                                   set: { model.change(entry.id, LibraryPatch(score: $0)) })) {
                    ForEach((1...10).reversed(), id: \.self) { n in Text("\(n)").tag(n * 10) }
                    Text("No score").tag(0)
                }
            } label: {
                Label("Rate", systemImage: "star")
            }
        }
        Section {
            if Harbor.plays(media) {
                Button {
                    if let url = Harbor.link(entry.title) { openURL(url) }
                } label: {
                    Label("Open in Harbor", systemImage: "play")
                }
            }
            Button {
                model.sheet = .addToList(entry.id)
            } label: {
                Label("Add to list", systemImage: "text.badge.plus")
            }
            Button {
                model.sheet = .sendTo(entry.id)
            } label: {
                Label("Send to a friend", systemImage: "paperplane")
            }
            ShareLink(item: Route.title(entry.id).url, subject: Text(entry.title.name)) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
        }
        if entry.status != .dropped {
            Section {
                Button(role: .destructive) {
                    model.change(entry.id, LibraryPatch(status: .dropped))
                } label: {
                    Label("Drop", systemImage: "xmark.circle")
                }
            }
        }
    }
}

/// Harbor (the PC's player) plays anime, TV and films; GupTrack hands it the title by link.
enum Harbor {
    static func plays(_ media: MediaKind) -> Bool { media == .anime || media == .tv || media == .movie }

    /// harbor://title/anime:210482
    static func link(_ title: Title) -> URL? { URL(string: "harbor://title/" + title.id) }
}
