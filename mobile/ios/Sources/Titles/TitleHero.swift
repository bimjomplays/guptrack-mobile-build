import SwiftUI

/// The top of a title page: the banner (a plain cut with a flat dark tint; books and titles without a banner get
/// their cover blurred), the cover, and the name with its lines.
struct TitleHero: View {
    let page: TitlePage

    private var t: Title { page.title }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TitleBackdrop(title: t)
                .frame(height: 272)
                .frame(maxWidth: .infinity)
                .clipped()
            HStack(alignment: .bottom, spacing: 16) {
                Poster(url: t.cover, width: 112)
                TitleHeroText(page: page)
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, 158)
        }
    }
}

/// the banner behind the hero
private struct TitleBackdrop: View {
    let title: Title

    var body: some View {
        if title.media != .book, let banner = title.banner {
            Artwork(url: banner).overlay(Color.black.opacity(0.4))
        } else {
            Artwork(url: title.cover, placeholder: Theme.panel)
                .blur(radius: 30, opaque: true)
                .scaleEffect(1.25)
                .overlay(Color.black.opacity(0.5))
        }
    }
}

private struct TitleHeroText: View {
    let page: TitlePage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(page.title.name)
                .font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.ink)
                .lineLimit(3).minimumScaleFactor(0.85)
                .accessibilityAddTraits(.isHeader)
            if let native = page.nativeLine {
                Text(native).font(.system(size: 13)).foregroundStyle(Theme.inkMuted).lineLimit(1).padding(.top, 3)
            }
            Text(page.metaLine).font(.system(size: 14)).foregroundStyle(Theme.inkSoft).lineLimit(1).padding(.top, 6)
            creatorLine.padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var creatorLine: some View {
        HStack(spacing: 6) {
            if let c = page.creatorName {
                Text(c).lineLimit(1)
            }
            if page.creatorName != nil, page.averageText != nil { Text("·") }
            if let avg = page.averageText {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Theme.star)
                    Text(avg).foregroundStyle(Theme.inkSoft).numbers()
                    if let out = page.averageOutOf { Text(out) }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
    }
}

// MARK: - the buttons under the hero

/// Open in Harbor / Mark Ch N read / Update progress, then send and add to a list.
struct TitleActions: View {
    let page: TitlePage

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    private var t: Title { page.title }

    var body: some View {
        let primary = TitlePrimary.of(t, entry: model.entry(t.id))
        HStack(spacing: 10) {
            Button { run(primary) } label: {
                Label(primary.label, systemImage: primary.symbol)
            }
            .buttonStyle(.capsule(.white, .regular, full: true))
            .disabled(primary == .allRead)
            TitleCircleButton(symbol: "paperplane", label: "Send to a friend") { model.sheet = .sendTo(t.id) }
            TitleCircleButton(symbol: "text.badge.plus", label: "Add to a list") { model.sheet = .addToList(t.id) }
        }
        .padding(.horizontal, Theme.pad)
    }

    private func run(_ p: TitlePrimary) {
        switch p {
        case .harbor:
            if let url = Harbor.link(t) { openURL(url) }
        case .markChapter(let n):
            if let e = model.entry(t.id) {
                var patch = LibraryPatch(progress: n)
                if e.status == .planned { patch.status = .current }
                if let total = t.total, n >= total { patch.status = .completed }
                model.change(t.id, patch)
            } else {
                model.change(t.id, LibraryPatch(status: .current, progress: n), title: t)
            }
        case .allRead:
            break
        case .updateProgress:
            model.sheet = .editor(t.id, expanded: false)
        case .startReading:
            model.change(t.id, LibraryPatch(status: .current), title: t)
        }
    }
}

/// a 44pt round grey button with an SF Symbol
struct TitleCircleButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 44
    var tint: Color = Theme.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Theme.fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
