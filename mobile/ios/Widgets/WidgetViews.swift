import SwiftUI

// The widgets' faces (65, 65b) as plain SwiftUI views that take a WidgetSnapshot value. The widget extension wraps
// them in its entry views (GupTrackWidgets.swift); the app compiles this file too, so the screen tests can draw them
// on a mock Home Screen and Lock Screen (Tests/ExtensionsMocks.swift). Nothing here uses WidgetKit or the app's Kit:
// pictures come through `art` (the widget passes images it downloaded first, the app its Artwork) and the +1
// button through `plus` (the widget's is a Button(intent:)).

/// the colours the widgets use (the app's Theme isn't in the extension)
enum WidgetInk {
    static let brand = Color(red: 10 / 255, green: 132 / 255, blue: 1)
    static let brandSoft = Color(red: 61 / 255, green: 155 / 255, blue: 1)
    static let ink = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let muted = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.55)
    static let track = Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255).opacity(0.3)
    static let bar = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.8)
    /// the medium widget's own background (the system draws it behind the content)
    static let background = Color(red: 24 / 255, green: 25 / 255, blue: 30 / 255)
}

/// the blue "+1" circle on a Continue row
struct WidgetPlusLabel: View {
    var body: some View {
        Text("+1")
            .font(.system(size: 15, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(WidgetInk.brand.opacity(0.9), in: Circle())
    }
}

/// Medium "Continue": the first two titles you're on, each with a +1.
struct ContinueWidgetView<Art: View, Plus: View>: View {
    let snapshot: WidgetSnapshot
    let art: (URL?) -> Art
    let plus: (WidgetSnapshot.Item) -> Plus

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if snapshot.items.isEmpty {
                Text("Nothing in Continue yet. Start something in GupTrack.")
                    .font(.system(size: 14))
                    .foregroundStyle(WidgetInk.muted)
                    .padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(snapshot.items.prefix(2)) { item in
                        ContinueWidgetRow(item: item, art: art, plus: plus)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 13)
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        Label {
            Text("Continue")
        } icon: {
            Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
        }
        .labelStyle(WidgetTightLabel(spacing: 6))
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(WidgetInk.brandSoft)
        .padding(.bottom, 10)
    }
}

/// one row of the Continue widget: cover, name, "Ep 6 of 11", bar, +1
struct ContinueWidgetRow<Art: View, Plus: View>: View {
    let item: WidgetSnapshot.Item
    let art: (URL?) -> Art
    let plus: (WidgetSnapshot.Item) -> Plus

    var body: some View {
        HStack(spacing: 11) {
            Link(destination: item.url) {
                HStack(spacing: 11) {
                    art(item.cover)
                        .frame(width: 38, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    words
                }
            }
            if item.canStep {
                plus(item).accessibilityLabel("Add one to \(item.name)")
            }
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WidgetInk.ink)
                .lineLimit(1)
            Text(item.caption)
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(WidgetInk.muted)
                .lineLimit(1)
                .padding(.top, 1)
                .padding(.bottom, 6)
            WidgetBar(fraction: item.fraction ?? 0)
                .opacity(item.fraction == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// the thin progress bar under a row
struct WidgetBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetInk.track)
                Capsule().fill(WidgetInk.bar).frame(width: max(0, min(1, fraction)) * g.size.width)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// Small "Next episode": the cover full bleed, the title and when the next episode airs.
struct NextEpisodeWidgetView<Art: View>: View {
    let spotlight: WidgetSnapshot.Spotlight?
    let art: (URL?) -> Art

    var body: some View {
        if let s = spotlight {
            filled(s)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Next episode")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WidgetInk.muted)
                Spacer(minLength: 0)
                Text("Nothing airing for you this week")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WidgetInk.ink)
            }
            .padding(13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func filled(_ s: WidgetSnapshot.Spotlight) -> some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { g in
                art(s.cover).frame(width: g.size.width, height: g.size.height).clipped()
            }
            // a flat shade over the cover so the words read (no gradient), the way Home's StartCard does it
            Color.black.opacity(0.45)
            Text(s.label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.leading, 13).padding(.top, 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(2)
                    .foregroundStyle(.white)
                Text(s.caption)
                    .font(.system(size: 13)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
            }
            .padding(.leading, 13).padding(.trailing, 12).padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Lock Screen rectangle: "Next episode", the title, "Ep 7 · Fri 3:00 AM".
struct NextEpisodeAccessoryView: View {
    let spotlight: WidgetSnapshot.Spotlight?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label {
                Text(spotlight?.label ?? "Next episode")
            } icon: {
                Image(systemName: "tv").font(.system(size: 11, weight: .semibold))
            }
            .labelStyle(WidgetTightLabel(spacing: 5))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(0.75))
            Text(spotlight?.name ?? "Nothing this week")
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .padding(.top, 2)
            if let s = spotlight {
                Text(s.caption)
                    .font(.system(size: 13)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Lock Screen circle: a ring of how far along, the number you're on and "of 11".
struct ProgressRingAccessoryView: View {
    let item: WidgetSnapshot.Item?

    var body: some View {
        ZStack {
            Circle().inset(by: 5.5).stroke(.white.opacity(0.22), lineWidth: 5)
            Circle().inset(by: 5.5)
                .trim(from: 0, to: item?.fraction ?? 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(item.map { Format.grouped($0.progress) } ?? "–")
                    .font(.system(size: 17, weight: .bold)).monospacedDigit()
                    .minimumScaleFactor(0.6)
                Text(item?.ringCaption ?? "")
                    .font(.system(size: 10)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.map { "\($0.name), \($0.caption)" } ?? "Nothing in Continue")
    }
}

/// Lock Screen line above the clock: "Ep 7 · Fri 3:00 AM · STEEL BALL RUN…"
struct NextEpisodeInlineView: View {
    let spotlight: WidgetSnapshot.Spotlight?

    var body: some View {
        Label(spotlight?.inline ?? "Nothing airing this week", systemImage: "tv")
    }
}

/// a Label with the icon closer to the words than the system's
struct WidgetTightLabel: LabelStyle {
    var spacing: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}
