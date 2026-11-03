import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share to GupTrack (66): reads what was shared (a link, text or both), matches it to a title (ShareMatch) and
/// shows ShareSheetView in a hosting controller.
///
/// Demo: it matches against the library and api/extensions.json bundled into the extension, and Add keeps the
/// change in the extension's own UserDefaults ("share-outbox") and closes. For the real app, Add writes to the App
/// Group's outbox (the app sends it like any offline change) and anything the demo can't match goes to the server's
/// link resolver; both need the App Group, which needs the signing team.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1)
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task { @MainActor in
            let shared = await Self.read(items)
            self.show(shared)
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

    private func show(_ shared: String) {
        let library = ExtensionsJSON.bundled([LibraryEntry].self, "library") ?? []
        let catalog = ExtensionsJSON.bundled(ExtensionCatalog.self, "extensions") ?? ExtensionCatalog()
        let found = ShareMatch.resolve(shared, library: library, catalog: catalog)
        let sheet = ShareSheetView(
            found: found,
            seasons: found.flatMap { catalog.seasons[$0.title.id] },
            art: { url in
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color(white: 0.17)
                }
            },
            onAdd: { [weak self] draft in self?.add(found, draft) },
            onCancel: { [weak self] in self?.cancel() })
        let host = UIHostingController(rootView: AnyView(sheet.preferredColorScheme(.dark).tint(ShareInk.brand)))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func add(_ found: ShareMatch.Found?, _ draft: ShareMatch.Draft) {
        if let found {
            let defaults = UserDefaults.standard
            var box = WidgetOutbox.load(defaults, key: "share-outbox")
            box.changes.append(WidgetOutbox.Change(id: found.title.id, patch: draft.patch, at: Clock.now))
            box.save(defaults, key: "share-outbox")
        }
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
}
