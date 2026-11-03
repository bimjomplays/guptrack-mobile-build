import SwiftUI

/// Signed out: the account screens (connect, sign in, join). Signed in: the five tabs, each with its own stack.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isSignedIn {
                tabs
            } else {
                AccountFlow()
            }
        }
        .sheet(item: $model.sheet) { route in
            SheetView(route: route)
        }
        .alert("GupTrack", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK", role: .cancel) { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
        .onOpenURL { url in model.handle(url: url) }
        // in front: send waiting changes and read the server's
        .task(id: phase == .active) {
            guard phase == .active, model.isSignedIn else { return }
            await model.refresh()
        }
    }

    private var tabs: some View {
        TabView(selection: Binding(get: { model.tab }, set: { picked in
            // tapping the tab you're on goes back to its first page
            if picked == model.tab { model.popToRoot(picked) }
            model.tab = picked
        })) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                TabStack(tab: .home) { HomeView() }
            }
            Tab("Browse", systemImage: "safari", value: AppTab.browse) {
                TabStack(tab: .browse) { BrowseView() }
            }
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                TabStack(tab: .library) { LibraryView() }
            }
            Tab("Social", systemImage: "person.2", value: AppTab.social) {
                TabStack(tab: .social) { SocialView() }
            }
            .badge(model.unreadMessages)
            Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                TabStack(tab: .profile) { ProfileView() }
            }
        }
    }
}

/// One tab's navigation stack, kept in the model so links and the demo's -open flag can set it.
struct TabStack<Root: View>: View {
    let tab: AppTab
    @ViewBuilder var root: () -> Root

    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack(path: Binding(get: { model.path(tab) }, set: { model.setPath(tab, $0) })) {
            root()
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }
}
