import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share to GupTrack (66): reads what was shared (a link, text or both), matches it to a title (ShareMatch) and
/// shows ShareSheetView in a hosting controller.
///
/// It matches against the library the app shares through the App Group (SharedBox) and, for a link that names
/// nothing there, asks the signed-in server (SharedServer: GET resolve, then the title). Add puts the change in the App
/// Group's outbox and closes; the app sends it like any offline change when it next comes to the front.
/// Without the App Group (unsigned simulator builds: the screen tests) it matches against the demo it bundles and
/// keeps Add in its own UserDefaults ("share-outbox").
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1)
        let source = ExtensionSource.current(SharedBox.app) {
            (ExtensionsJSON.bundledLibrary(),
             ExtensionsJSON.bundled(ExtensionCatalog.self, "extensions") ?? ExtensionCatalog())
        }
        // the demo data is recorded for Tue Nov 3, 2026, 9:41 AM in New York
        Clock.fixed = source.demo ? Clock.demoNow : nil
        Clock.fixedZone = source.demo ? Clock.demoZone : nil
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task { @MainActor in
            let shared = await Self.read(items)
            let found = await Self.match(shared, in: source)
            self.show(found, from: source)
        }
    }

    /// the shared link first, then any text (a page's title, a message)
    static func read(_ items: [NSExtensionItem]) async -> String {
        var links: [String] = []
        var texts: [String] = []
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    links.append(url.absoluteString)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    texts.append(text)
                }
            }
            if let text = item.attributedContentText?.string, !text.isEmpty { texts.append(text) }
        }
        return (links + texts).joined(separator: "\n")
    }

    /// the shared library first; a link it doesn't know goes to the server (signed in, not the demo)
    static func match(_ shared: String, in source: ExtensionSource) async -> ShareMatch.Found? {
        let found = ShareMatch.resolve(shared, library: source.library, catalog: source.catalog)
        if found?.how == .link || !source.usesBox || source.demo || !source.signedIn { return found }
        guard let link = ShareMatch.firstURL(in: shared), let account = SharedAccount.load(),
              let title = await SharedServer(account: account).title(for: link.absoluteString) else { return found }
        return ShareMatch.Found(title: title, how: .link, link: ShareMatch.label(link),
                                entry: source.library.first { $0.id == title.id })
    }

    private func show(_ found: ShareMatch.Found?, from source: ExtensionSource) {
        let account = source.usesBox ? SharedAccount.load() : nil
        let sheet = ShareSheetView(
            found: found,
            seasons: found.flatMap { source.catalog.seasons[$0.title.id] },
            art: { url in SharePicture(request: url.map { account?.request(for: $0) ?? URLRequest(url: $0) }) },
            onAdd: { [weak self] draft in self?.add(found, draft, to: source) },
            onCancel: { [weak self] in self?.cancel() })
        let host = UIHostingController(rootView: AnyView(sheet.preferredColorScheme(.dark).tint(ShareInk.brand)))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func add(_ found: ShareMatch.Found?, _ draft: ShareMatch.Draft, to source: ExtensionSource) {
        // signed out, nothing is kept (it would land on whichever account signs in next)
        if let found, source.signedIn {
            let change = WidgetOutbox.Change(id: found.title.id, patch: draft.patch, at: Clock.now, title: found.title)
            if source.usesBox, let box = SharedBox.app {
                box.append(change)
            } else {
                let defaults = UserDefaults.standard
                var box = WidgetOutbox.load(defaults, key: "share-outbox")
                box.changes.append(change)
                box.save(defaults, key: "share-outbox")
            }
        }
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
}

/// a cover for the sheet; GupTrack's own pictures come from the server with the token (AsyncImage can't send it)
struct SharePicture: View {
    let request: URLRequest?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(white: 0.17)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
        }
        .task(id: request?.url) {
            guard let request, request.url?.scheme != nil,
                  let (data, _) = try? await URLSession.shared.data(for: request) else { return }
            image = UIImage(data: data)
        }
    }
}
