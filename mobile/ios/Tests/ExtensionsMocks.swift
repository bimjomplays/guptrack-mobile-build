import SwiftUI
@testable import GupTrack

// Test-only stand-ins for the system's Home Screen and Lock Screen, to draw the widgets' faces where the mockups
// have them (65, 65b), and the page a link was shared from (66). Flat coloured tiles with a plain symbol, no
// gradients and nothing that copies the system's own icons. The widgets read the app's library, so a +1 here goes through AppModel.step.

/// the demo catalogue the extensions bundle (api/extensions.json)
@MainActor
enum ExtensionsDemo {
    static var catalog: ExtensionCatalog {
        (try? Demo.load(ExtensionCatalog.self, "api/extensions.json")) ?? ExtensionCatalog()
    }
}

/// an app tile: a flat colour with a plain symbol, its name under it
private struct MockAppTile: View {
    let name: String
    var symbol: String = ""
    var color: Color = Color(white: 0.27)
    var size: CGFloat = 62

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                .fill(color)
                .frame(width: size, height: size)
                .overlay {
                    if !symbol.isEmpty {
                        Image(systemName: symbol).font(.system(size: size * 0.42, weight: .regular))
                            .foregroundStyle(.white)
                    }
                }
            if !name.isEmpty {
                Text(name).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
            }
        }
        .frame(width: 82)
    }
}

/// the made-up apps round the widgets: name, symbol, colour
private enum MockApps {
    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
    static let harbor = ("Harbor", "ferry", rgb(26, 42, 74))
    static let gupworks = ("GupWorks", "sparkles", rgb(52, 36, 92))
    static let camera = ("Camera", "camera.aperture", rgb(52, 54, 60))
    static let row1 = [("Gallery", "photo.on.rectangle", rgb(178, 66, 66)), ("Music", "waveform", rgb(196, 44, 92)),
                       ("Notes", "square.and.pencil", rgb(196, 140, 34)), ("Weather", "cloud.sun", rgb(44, 102, 196))]
    static let row2 = [("Maps", "map", rgb(34, 128, 84)), ("Bank", "building.columns", rgb(26, 90, 94)),
                       ("Fitness", "waveform.path.ecg", rgb(214, 88, 36)), ("Files", "folder", rgb(52, 96, 196))]
    static let dock = [("", "phone", rgb(40, 160, 72)), ("", "bubble.left", rgb(52, 112, 230)),
                       ("", "globe", rgb(56, 132, 214)), ("", "envelope", rgb(84, 90, 102))]
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
        tile(MockApps.harbor).offset(x: Self.cols[3] - 10, y: 262)
        tile(MockApps.gupworks).offset(x: Self.cols[2] - 10, y: 358)
        tile(MockApps.camera).offset(x: Self.cols[3] - 10, y: 358)
        ForEach(Array(MockApps.row1.enumerated()), id: \.offset) { i, app in
            tile(app).offset(x: Self.cols[i] - 10, y: 466)
        }
        ForEach(Array(MockApps.row2.enumerated()), id: \.offset) { i, app in
            tile(app).offset(x: Self.cols[i] - 10, y: 562)
        }
    }

    private func tile(_ app: (String, String, Color)) -> MockAppTile {
        MockAppTile(name: app.0, symbol: app.1, color: app.2)
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
            ForEach(Array(MockApps.dock.enumerated()), id: \.offset) { _, app in tile(app).frame(width: 62) }
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
                if let n = message { notification(n).padding(.horizontal, 10).padding(.bottom, 20) }
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

    /// the newest message from the demo bell, as its notification
    private var message: BellNotice? {
        ((try? Demo.load([BellNotice].self, "api/notices.json")) ?? []).first { $0.kind == .message }
    }

    private func notification(_ n: BellNotice) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(white: 0.09))
                .frame(width: 38, height: 38)
                .overlay {
                    ZStack {
                        Circle().stroke(.white.opacity(0.12), lineWidth: 3).frame(width: 19, height: 19)
                        Circle().trim(from: 0, to: 0.8)
                            .stroke(WidgetInk.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90)).frame(width: 19, height: 19)
                        Text("G").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                    }
                }
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(n.user ?? n.title).font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(Format.agoLong(n.date)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                }
                Text(n.text).font(.system(size: 15)).lineLimit(2)
            }
            .foregroundStyle(.white)
            Artwork(url: n.cover)
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(14)
        .background(Color(white: 0.13).opacity(0.92), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
