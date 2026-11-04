import SwiftUI
import UIKit

/// Posters, banners and avatars from the catalogue CDNs (AniList, TMDB, Open Library) and GupTrack's own pictures
/// (avatars, banners, message photos: with the token), loaded at runtime and kept in memory and in Caches. Nothing is
/// bundled. Offline (or without a URL) a neutral placeholder shows instead. GupTrack's own are kept apart, asked again
/// once a launch (PictureFetch: a 404 drops the copy) and forgotten when this phone is signed out.
@MainActor
final class ImageLoader {
    static let shared = ImageLoader()

    /// pictures on the way (the screen tests wait for 0)
    private(set) var inFlight = 0

    private let memory = NSCache<NSURL, UIImage>()
    private var tasks: [URL: Task<UIImage?, Never>] = [:]
    /// own pictures asked again this launch
    private var checked: Set<URL> = []
    private let session: URLSession
    private let dir: URL
    private let own: URL
    private var signedOut: NSObjectProtocol?

    init() {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: c)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = caches.appendingPathComponent("artwork", isDirectory: true)
        own = caches.appendingPathComponent("artwork-own", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        memory.countLimit = 400
        signedOut = NotificationCenter.default.addObserver(forName: .gupTrackSignedOut, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ImageLoader.shared.forgetOwn() }
        }
    }

    /// signed out: nothing of that account's pictures stays on the phone
    func forgetOwn() {
        memory.removeAllObjects()
        checked = []
        try? FileManager.default.removeItem(at: own)
        try? FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
    }

    /// already here (memory only), for a first frame without a flash
    func cached(_ url: URL) -> UIImage? { Pictures.resolve(url).flatMap { memory.object(forKey: $0 as NSURL) } }

    func image(_ given: URL) async -> UIImage? {
        // GupTrack's own pictures ("/media/…") come from the signed-in server, with the token (docs/app-api.md §5)
        guard let url = Pictures.resolve(given) else { return nil }
        let auth = Pictures.authorization(for: url)
        let mine = PictureFetch.revalidates(authorization: auth)
        if let hit = memory.object(forKey: url as NSURL) {
            if mine { recheck(url, auth: auth) }
            return hit
        }
        if let running = tasks[url] { return await running.value }
        let file = (mine ? own : dir).appendingPathComponent(Self.key(url))
        inFlight += 1
        let session = session
        let task = Task<UIImage?, Never>.detached(priority: .userInitiated) {
            if let d = try? Data(contentsOf: file), let img = UIImage(data: d) { return img }
            let request = mine ? PictureFetch.request(url, authorization: auth, cached: false) : Self.plain(url)
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  let img = UIImage(data: data) else { return nil }
            try? data.write(to: file, options: .atomic)
            return img
        }
        tasks[url] = task
        let img = await task.value
        tasks[url] = nil
        inFlight -= 1
        if let img { memory.setObject(img, forKey: url as NSURL) }
        if mine { recheck(url, auth: auth) }
        return img
    }

    private nonisolated static func plain(_ url: URL) -> URLRequest { URLRequest(url: url) }

    /// an own picture shown from the phone's copy: asked again once a launch, in the background
    private func recheck(_ url: URL, auth: String?) {
        guard !Demo.isOn, !checked.contains(url) else { return }
        checked.insert(url)
        let file = own.appendingPathComponent(Self.key(url))
        let cached = FileManager.default.fileExists(atPath: file.path)
        let request = PictureFetch.request(url, authorization: auth, cached: cached)
        let session = session
        Task.detached(priority: .utility) {
            let answer = try? await session.data(for: request)
            let status = (answer?.1 as? HTTPURLResponse)?.statusCode
            let outcome = PictureFetch.outcome(status: status, data: answer?.0, cached: cached)
            await MainActor.run { ImageLoader.shared.settle(url, file: file, outcome) }
        }
    }

    private func settle(_ url: URL, file: URL, _ outcome: PictureFetch.Outcome) {
        switch outcome {
        case .keep:
            break
        case .fresh(let data):
            guard let img = UIImage(data: data) else { return }
            try? data.write(to: file, options: .atomic)
            memory.setObject(img, forKey: url as NSURL)
        case .drop:
            try? FileManager.default.removeItem(at: file)
            memory.removeObject(forKey: url as NSURL)
        }
    }

    /// a file name for a URL (its host and path, made safe)
    nonisolated static func key(_ url: URL) -> String {
        let raw = (url.host ?? "") + url.path
        return String(raw.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }.suffix(180))
    }
}

/// a picture from a URL that fills its frame (cropped), with the placeholder until it's here
struct Artwork: View {
    let url: URL?
    var placeholder: Color = Theme.raised

    @State private var image: UIImage?

    var body: some View {
        Rectangle().fill(placeholder)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: url) {
                guard let url else { image = nil; return }
                if let hit = ImageLoader.shared.cached(url) { image = hit; return }
                image = await ImageLoader.shared.image(url)
            }
            .accessibilityHidden(true)
    }
}

/// Poster or cover art: rounded, with the website's keyline and a soft shadow.
struct Poster: View {
    let url: URL?
    var width: CGFloat = 110
    var ratio: CGFloat = 1.5
    var radius: CGFloat = 10
    /// rows use the flat one (no shadow)
    var flat = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Artwork(url: url)
            .frame(width: width, height: (width * ratio).rounded())
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.keyline, lineWidth: 0.5))
            .shadow(color: .black.opacity(flat ? 0 : 0.3), radius: 5, y: 2)
    }
}

/// A user's picture: square with the website's rounded corners. `ring` marks one picked (send-to).
struct Avatar: View {
    let url: URL?
    var size: CGFloat = 40
    var ring = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: (size * 0.3).rounded(), style: .continuous)
        Artwork(url: url)
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.keyline, lineWidth: 0.5))
            .padding(ring ? 3 : 0)
            .overlay { if ring { shape.inset(by: -0.5).strokeBorder(Theme.color(.current), lineWidth: 1.5) } }
    }
}

/// A poster with its title and a caption under it, for shelves. `badge` sits on the art's top left.
struct PosterCard<Caption: View>: View {
    let url: URL?
    let title: String
    var width: CGFloat = 118
    var ratio: CGFloat = 1.5
    var badge: String?
    var progress: Double?
    @ViewBuilder var caption: () -> Caption

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Poster(url: url, width: width, ratio: ratio)
                .overlay(alignment: .topLeading) {
                    if let badge {
                        Text(badge).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let progress {
                        ProgressBar(fraction: progress, color: .white).padding(8)
                    }
                }
            Text(title).font(.cardTitle).foregroundStyle(Theme.ink).lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 8)
            caption().font(.cardCaption).foregroundStyle(Theme.inkMuted).lineLimit(1).padding(.top, 1)
        }
        .frame(width: width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension PosterCard where Caption == Text {
    init(url: URL?, title: String, caption: String?, width: CGFloat = 118, ratio: CGFloat = 1.5, badge: String? = nil,
         progress: Double? = nil) {
        self.init(url: url, title: title, width: width, ratio: ratio, badge: badge, progress: progress,
                  caption: { Text(caption ?? "") })
    }
}

/// a horizontal shelf of cards that scrolls past the screen's edge
struct Shelf<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: spacing) { content() }
                .padding(.horizontal, Theme.pad)
        }
        .scrollClipDisabled()
    }
}
