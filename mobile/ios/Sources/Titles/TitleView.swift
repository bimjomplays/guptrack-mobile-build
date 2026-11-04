import SwiftUI

/// A title's page (16-25): one layout for anime, manga, TV, films and books. The page comes from the server; "Your
/// list" is the offline library's. When the page can't load but the title is on the list, the page is drawn from the
/// library's copy of the title.
struct TitleView: View {
    let id: String

    @Environment(AppModel.self) private var model
    @State private var state: Load<TitlePage> = .loading

    var body: some View {
        Group {
            if let page = shown {
                TitlePageBody(page: page, reload: load)
            } else if let why = state.error {
                ContentUnavailableView {
                    Label("Couldn't load this", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(why)
                } actions: {
                    Button("Try again") { Task { await load() } }.buttonStyle(.capsule(.tone, .small))
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .pageBackground()
        .task(id: id) {
            if state.value == nil { await load() }
        }
    }

    /// the loaded page, else one from the library's copy once loading failed
    private var shown: TitlePage? {
        if let p = state.value { return p }
        if state.error != nil, let t = model.entry(id)?.title { return .basic(t) }
        return nil
    }

    private func load() async {
        let id = id
        let next = await model.fetch { try await $0.titlePage(id) }
        if next.value != nil || state.value == nil { state = next }
    }
}

/// the page itself: hero, your list, then the sections
private struct TitlePageBody: View {
    let page: TitlePage
    let reload: () async -> Void

    @Environment(AppModel.self) private var model
    @State private var scrolled = false
    @State private var confirmRemove = false

    private var t: Title { page.title }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TitleHero(page: page)
                TitleActions(page: page).padding(.top, 16)
                TitleListStrip(page: page).padding(.top, 18)
                TitleInfoLine(page: page).padding(.top, 16)
                TitleSections(page: page)
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .onScrollGeometryChange(for: Bool.self) { g in
            g.contentOffset.y + g.contentInsets.top > 250
        } action: { _, now in
            scrolled = now
        }
        .refreshable { await reload() }
        .navigationTitle(page.title.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(page.title.name).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    .opacity(scrolled ? 1 : 0)
                    .accessibilityHidden(!scrolled)
            }
            // two items, not a group: each is its own bar button (the bar still draws them in one capsule), so
            // the More menu opens on its own tap
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: Route.title(page.title.id).url, subject: Text(page.title.name)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    TitleMoreItems(page: page, confirmRemove: $confirmRemove)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .confirmationDialog("Remove \(t.name) from your list?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove from list", role: .destructive) { model.change(t.id, LibraryPatch(remove: true)) }
        } message: {
            Text("Your progress, score and dates for it go too.")
        }
    }
}

/// ••• (20): Harbor, lists, send, share, copy | review, the title elsewhere | remove
struct TitleMoreItems: View {
    let page: TitlePage
    @Binding var confirmRemove: Bool

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    private var t: Title { page.title }

    var body: some View {
            Section {
                if Harbor.plays(t.media), let url = Harbor.link(t) {
                    Button { openURL(url) } label: { Label("Open in Harbor", systemImage: "play") }
                }
                Button { model.sheet = .addToList(t.id) } label: { Label("Add to a list…", systemImage: "text.badge.plus") }
                Button { model.sheet = .sendTo(t.id) } label: { Label("Send to a friend", systemImage: "paperplane") }
                ShareLink(item: Route.title(t.id).url, subject: Text(t.name)) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                Button { UIPasteboard.general.url = Route.title(t.id).url } label: { Label("Copy link", systemImage: "link") }
            }
            Section {
                Button { model.sheet = .writeReview(t.id) } label: { Label("Write a review", systemImage: "square.and.pencil") }
                ForEach(page.openLinks, id: \.self) { link in
                    Button { openURL(link.url) } label: { Label("Open on \(link.label)", systemImage: "arrow.up.right.square") }
                }
            }
            if model.entry(t.id) != nil {
                Section {
                    Button(role: .destructive) { confirmRemove = true } label: {
                        Label("Remove from list", systemImage: "trash")
                    }
                }
            }
    }
}
