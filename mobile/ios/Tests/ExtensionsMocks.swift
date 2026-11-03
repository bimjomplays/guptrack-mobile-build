import SwiftUI
@testable import GupTrack

// Test-only stand-ins for the system's Home Screen and Lock Screen, to draw the widgets' faces where the mockups
// have them (65, 65b), and the page a link was shared from (66). Flat colours and plain grey tiles: nothing that
// copies the system's own icons. The widgets read the app's library, so a +1 here goes through AppModel.step.

/// the demo catalogue the extensions bundle (api/extensions.json)
@MainActor
enum ExtensionsDemo {
    static var catalog: ExtensionCatalog {
        (try? Demo.load(ExtensionCatalog.self, "api/extensions.json")) ?? ExtensionCatalog()
    }
}

/// a grey app tile with its name under it
private struct MockAppTile: View {
    let name: String
    var size: CGFloat = 62

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                .fill(Color(white: 0.27))
                .frame(width: size, height: size)
            if !name.isEmpty {
                Text(name).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
            }
        }
        .frame(width: 82)
    }
}

/// GupTrack's own tile: a dark square with a blue progress arc round a G
private struct MockGupTrackTile: View {
    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 14.6, style: .continuous)
                .fill(Color(white: 0.09))
                .frame(width: 62, height: 62)
                .overlay {
                    ZStack {
                        Circle().stroke(.white.opacity(0.12), lineWidth: 4.5).frame(width: 30, height: 30)
                        Circle().trim(from: 0, to: 0.8).stroke(WidgetInk.brand, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                            .rotationEffect(.degrees(-90)).frame(width: 30, height: 30)
                        Text("G").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                    }
                }
            Text("GupTrack").font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
        }
        .frame(width: 82)
    }
}

/// a widget's frame on the Home Screen: rounded, the widget's background, its name under it
private struct MockWidgetFrame<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    var background: Color = WidgetInk.background
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 6) {
            content
                .frame(width: width, height: height)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text("GupTrack").font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
        }
    }
}

/// 65: the Home Screen with the medium Continue widget and the small Next episode widget
struct MockHomeScreen: View {
    @Environment(AppModel.self) private var model

    private var snapshot: WidgetSnapshot {
        WidgetSnapshot.make(library: model.library, catalog: ExtensionsDemo.catalog, now: Clock.now)
    }

    private static let cols: [CGFloat] = [28, 122.7, 217.3, 312]

    var body: some View {
        let snap = snapshot
        ZStack(alignment: .topLeading) {
            Color(red: 21 / 255, green: 20 / 255, blue: 38 / 255)
            MockWidgetFrame(width: 354, height: 166) {
                ContinueWidgetView(snapshot: snap, art: { Artwork(url: $0) }, plus: plusButton)
            }
            .offset(x: 24, y: 68)
            MockWidgetFrame(width: 166, height: 166, background: .black) {
                NextEpisodeWidgetView(spotlight: snap.spotlight, art: { Artwork(url: $0) })
            }
            .offset(x: 24, y: 262)
            apps
            searchPill.frame(maxWidth: .infinity).offset(y: 676)
            dock
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }

    private func plusButton(_ item: WidgetSnapshot.Item) -> some View {
        Button { model.step(item.id) } label: { WidgetPlusLabel() }
            .buttonStyle(.plain)
    }

    @ViewBuilder private var apps: some View {
        MockGupTrackTile().offset(x: Self.cols[2] - 10, y: 262)
        MockAppTile(name: "Harbor").offset(x: Self.cols[3] - 10, y: 262)
        MockAppTile(name: "GupWorks").offset(x: Self.cols[2] - 10, y: 358)
        MockAppTile(name: "Camera").offset(x: Self.cols[3] - 10, y: 358)
        ForEach(Array(["Gallery", "Music", "Notes", "Weather"].enumerated()), id: \.offset) { i, name in
            MockAppTile(name: name).offset(x: Self.cols[i] - 10, y: 466)
        }
        ForEach(Array(["Maps", "Bank", "Fitness", "Files"].enumerated()), id: \.offset) { i, name in
            MockAppTile(name: name).offset(x: Self.cols[i] - 10, y: 562)
        }
    }

    private var searchPill: some View {
        Label("Search", systemImage: "magnifyingglass")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(Color(white: 0.2), in: Capsule())
    }

    private var dock: some View {
        HStack {
            ForEach(0..<4, id: \.self) { _ in MockAppTile(name: "").frame(width: 62) }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .frame(height: 94)
        .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 38, style: .continuous))
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 14)
    }
}

/// 65b: the Lock Screen with the Next episode rectangle and two Progress rings
struct MockLockScreen: View {
    @Environment(AppModel.self) private var model

    private var snapshot: WidgetSnapshot {
        WidgetSnapshot.make(library: model.library, catalog: ExtensionsDemo.catalog, now: Clock.now)
    }

    private var dateLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = Clock.zone
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: Clock.now)
    }

    var body: some View {
        let snap = snapshot
        ZStack(alignment: .top) {
            Color(red: 11 / 255, green: 17 / 255, blue: 32 / 255)
            VStack(spacing: 0) {
                Text(dateLine)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 78)
                Text(Format.time(Clock.now).replacingOccurrences(of: " AM", with: "").replacingOccurrences(of: " PM", with: ""))
                    .font(.system(size: 104, weight: .bold)).monospacedDigit()
                    .kerning(-4)
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(height: 116)
                HStack(spacing: 12) {
                    NextEpisodeAccessoryView(spotlight: snap.spotlight)
                        .padding(.horizontal, 12)
                        .frame(width: 170, height: 66)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    ForEach(snap.items.prefix(2)) { item in
                        ProgressRingAccessoryView(item: item)
                            .frame(width: 66, height: 66)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                }
                .padding(.top, 22)
                Spacer()
                HStack {
                    lockButton("flashlight.off.fill")
                    Spacer()
                    lockButton("camera.fill")
                }
                .padding(.horizontal, 46)
                .padding(.bottom, 48)
            }
        }
        .ignoresSafeArea()
    }

    private func lockButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20))
            .foregroundStyle(.white)
            .frame(width: 50, height: 50)
            .background(.white.opacity(0.14), in: Circle())
    }
}

/// 66: the page the link was shared from (a title's page in some browser) with Share to GupTrack over it
struct MockSharePage: View {
    let shared: String
    var onAdd: (ShareMatch.Draft) -> Void = { _ in }
    var onCancel: () -> Void = {}

    @Environment(AppModel.self) private var model

    var body: some View {
        let catalog = ExtensionsDemo.catalog
        let found = ShareMatch.resolve(shared, library: model.library, catalog: catalog)
        behind(found?.title)
            .sheet(isPresented: .constant(true)) {
                ShareSheetView(found: found, seasons: found.flatMap { catalog.seasons[$0.title.id] },
                               art: { Artwork(url: $0) }, onAdd: onAdd, onCancel: onCancel)
                    .presentationDetents([.height(560)])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
    }

    private func behind(_ t: Title?) -> some View {
        ZStack(alignment: .topLeading) {
            Color(red: 14 / 255, green: 15 / 255, blue: 18 / 255)
            Artwork(url: t?.banner ?? t?.cover).frame(maxWidth: .infinity).frame(height: 300)
            VStack(alignment: .leading, spacing: 4) {
                Text(t?.name ?? "").font(.system(size: 30, weight: .heavy)).foregroundStyle(.white)
                Text(([t?.year.map(String.init)] + (t?.genres ?? []).prefix(3).map { Optional($0) }).compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.system(size: 15)).foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 20)
            .offset(y: 300)
        }
        .ignoresSafeArea()
    }
}
