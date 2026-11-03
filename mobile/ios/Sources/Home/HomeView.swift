import SwiftUI

/// Home (05, 06): Continue first, as on the website, then Upcoming, Stalled, Start something and Trending. Calendar
/// and notifications sit in the toolbar. Continue and Stalled come from the offline library; Upcoming and Trending
/// from GET home/live; Start something from POST home/picks (docs/app-api.md §6).
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var live: HomeLive?
    @State private var picks: [OnTheGo]?
    @State private var shuffle = 0

    var body: some View {
        let lib = model.library
        let continuing = HomeShelves.continuing(lib)
        let upcoming = HomeShelves.upcoming(live?.upcoming ?? [], library: lib)
        let stalled = HomeShelves.stalled(lib)
        let starts = HomeShelves.startCandidates(picks, library: lib)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if continuing.isEmpty && stalled.isEmpty {
                    emptyLibrary
                } else {
                    SectionHeader(title: "Continue", action: { openList(continuing.first?.media ?? .anime) }) {
                        Text("\(HomeShelves.inProgress(lib).count) in progress")
                            .font(.system(size: 15)).foregroundStyle(Theme.inkMuted).numbers()
                    }
                    ForEach(Array(continuing.prefix(4).enumerated()), id: \.element.id) { i, e in
                        ContinueRow(entry: e, separator: i < min(continuing.count, 4) - 1)
                    }
                }
                if !upcoming.isEmpty {
                    SectionHeader("Upcoming", sub: "Next episodes of what you watch", chevron: false)
                        .sectionGap()
                    Shelf {
                        ForEach(upcoming.prefix(10), id: \.titleId) { n in
                            let e = model.entry(n.titleId)
                            NavigationLink(value: Route.title(n.titleId)) {
                                PosterCard(url: e?.title.cover ?? n.cover, title: e?.title.name ?? n.title,
                                           caption: HomeShelves.upcomingCaption(n))
                            }
                            .buttonStyle(.plain)
                            .contextMenu { if let e { EntryMenu(entry: e) } }
                        }
                    }
                }
                if !stalled.isEmpty {
                    SectionHeader("Stalled", sub: "No progress in 30+ days", chevron: false)
                        .sectionGap(34)
                    VStack(spacing: 18) {
                        ForEach(stalled.prefix(3)) { e in StalledRow(entry: e) }
                    }
                }
                if !starts.isEmpty {
                    let pick = starts[shuffle % starts.count]
                    SectionHeader("Start something", sub: "From your \(ListStatus.planned.label(pick.media))", chevron: false)
                        .sectionGap(34)
                    StartCard(entry: pick, canShuffle: starts.count > 1) { shuffle += 1 }
                }
                if let live, !live.trending.isEmpty {
                    SectionHeader("Trending anime", chevron: false).sectionGap(34)
                    Shelf {
                        ForEach(live.trending) { t in
                            NavigationLink(value: Route.title(t.id)) {
                                PosterCard(url: t.cover, title: t.title, caption: t.note.isEmpty ? nil : t.note)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .pageBackground()
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    model.open(.calendar)
                } label: {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("Calendar")
                Button {
                    model.open(.notifications)
                } label: {
                    Image(systemName: "bell")
                        .overlay(alignment: .topTrailing) {
                            if model.unreadNotifications > 0 {
                                Circle().fill(Theme.danger).frame(width: 9, height: 9).offset(x: 3, y: -2)
                            }
                        }
                }
                .accessibilityLabel("Notifications")
            }
        }
        .task { await load(counts: live == nil) }
        .refreshable {
            await model.refresh()
            await load(counts: true)
        }
    }

    /// `counts`: also take the bell's unseen count from GET notices (first load and pull to refresh; coming back
    /// from Notifications keeps what was seen there). Picks avoid what Start something showed before.
    private func load(counts: Bool) async {
        if let v = await model.fetch({ try await $0.homeLive() }).value { live = v }
        let shown = Array((picks ?? []).map(\.titleId).prefix(shuffle + 1))
        if let v = await model.fetch({ try await $0.picks(avoid: HomeShelves.avoid(shown)) }).value {
            picks = v
            shuffle = 0
        }
        if counts, let n = await model.fetch({ try await $0.notices() }).value {
            model.unreadNotifications = NoticeSection.unseen(n)
        }
    }

    private func openList(_ media: MediaKind) {
        model.setPath(.library, [.list(media)])
        model.tab = .library
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("Nothing in progress", systemImage: "play.square.stack")
        } description: {
            Text("Titles you start show up here. Find something in Browse.")
        } actions: {
            Button("Browse") { model.tab = .browse }.buttonStyle(.capsule(.tint, .small))
        }
        .padding(.top, 40)
    }
}

/// One row of Continue (05): cover, title, what's left, the progress bar, then status and the +/- stepper. A long
/// press shows the title's menu (07).
struct ContinueRow: View {
    let entry: LibraryEntry
    var separator = true

    @Environment(AppModel.self) private var model

    var body: some View {
        let e = entry
        HStack(alignment: .top, spacing: 14) {
            Poster(url: e.title.cover, width: 60, radius: 8, flat: true)
                .padding(.vertical, 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(e.title.name).font(.rowTitle).foregroundStyle(Theme.ink).lineLimit(1)
                Text(e.continueLine).font(.caption14).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    .padding(.top, 1)
                ProgressBar(fraction: e.fraction ?? 0.62)
                    .padding(.top, 10).padding(.bottom, 9)
                HStack {
                    StatusPill(status: e.status, media: e.media, small: true) { s in
                        model.change(e.id, LibraryPatch(status: s))
                    }
                    Spacer()
                    if e.media != .movie {
                        ProgressStepper(progress: e.progress, total: e.title.total, small: true,
                                        minus: { model.step(e.id, by: -1) }, plus: { model.step(e.id) })
                    }
                }
            }
            .padding(.top, 12).padding(.bottom, 10)
            .overlay(alignment: .bottom) { if separator { Hairline() } }
        }
        .padding(.horizontal, Theme.pad)
        .contentShape(Rectangle())
        .onTapGesture { model.open(.title(e.id)) }
        .contextMenu { EntryMenu(entry: e) }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open") { model.open(.title(e.id)) }
    }
}

/// A Stalled row (06): "Ep 52 of 220 · last watched Jun 2024", Resume or Drop.
struct StalledRow: View {
    let entry: LibraryEntry

    @Environment(AppModel.self) private var model

    var body: some View {
        let e = entry
        HStack(spacing: 14) {
            Poster(url: e.title.cover, width: 52, radius: 7, flat: true)
            VStack(alignment: .leading, spacing: 0) {
                Text(e.title.name).font(.rowTitle).foregroundStyle(Theme.ink).lineLimit(1)
                Text(line).font(.caption14).foregroundStyle(Theme.inkMuted).lineLimit(1).numbers()
                    .padding(.top, 1)
                HStack(spacing: 8) {
                    Button {
                        model.change(e.id, LibraryPatch(status: .current))
                        model.open(.title(e.id))
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(.capsule(.tone, .small))
                    Button("Drop") { model.change(e.id, LibraryPatch(status: .dropped)) }
                        .buttonStyle(.capsule(.tone, .small, color: Theme.color(.dropped)))
                }
                .padding(.top, 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pad)
        .contentShape(Rectangle())
        .onTapGesture { model.open(.title(e.id)) }
        .contextMenu { EntryMenu(entry: e) }
    }

    private var line: String {
        let e = entry
        var at = "\(e.media.unitShort) \(Format.grouped(e.progress))"
        if let t = e.title.total { at += " of \(Format.grouped(t))" }
        let verb = e.media.isReading ? "read" : "watched"
        return "\(at) · last \(verb) \(Format.monthYear(e.updatedAt))"
    }
}

/// Start something (06): the title's art, the poster and title over its foot, Start and Shuffle. A flat dark layer
/// keeps the words readable (no gradient). The library carries no banner, so the art is the cover, cropped wide.
struct StartCard: View {
    let entry: LibraryEntry
    var canShuffle = true
    var shuffle: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        let t = entry.title
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Artwork(url: t.cover)
            .overlay(Color.black.opacity(0.45))
            .frame(height: 214)
            .overlay(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 14) {
                    Poster(url: t.cover, width: 64, radius: 8)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(t.name).font(.system(size: 18, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                        Text(HomeShelves.startLine(t)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1).padding(.top, 2)
                        HStack(spacing: 8) {
                            Button {
                                model.change(entry.id, LibraryPatch(status: .current))
                                model.open(.title(entry.id))
                            } label: {
                                Label("Start", systemImage: "play.fill")
                            }
                            .buttonStyle(.capsule(.white, .small))
                            if canShuffle {
                                Button(action: shuffle) {
                                    Label("Shuffle", systemImage: "shuffle")
                                }
                                .buttonStyle(.capsule(.tone, .small, color: .white))
                            }
                        }
                        .padding(.top, 10)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.keyline, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
            .padding(.horizontal, Theme.pad)
            .contentShape(shape)
            .onTapGesture { model.open(.title(entry.id)) }
            .contextMenu { EntryMenu(entry: entry) }
    }
}
