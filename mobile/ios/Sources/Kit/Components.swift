import SwiftUI

extension Binding {
    /// the loaded value of a page's `Load` state, to edit in place. It reads the state each time (not the copy the
    /// page was drawn with), so two edits in one action both stick.
    func current<T>(_ drawn: T) -> Binding<T> where Value == Load<T> {
        Binding<T>(get: { wrappedValue.value ?? drawn }, set: { wrappedValue = .loaded($0) })
    }
}

// GupTrack's own parts, as drawn in design/iphone/kit/kit.mjs: the status pill, the stepper, section headers,
// progress bars, scores, chips, plain hairline rows. Every screen builds from these so they look the same everywhere.
// The design no-list holds for all of them: no boxes inside boxes, no ALL-CAPS labels, no KPI tiles, no gradients, no
// glows, no glass on content (glass is only the system's own bars, buttons and sheets).

// MARK: status

/// the status colour's dot
struct StatusDot: View {
    let status: ListStatus
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(Theme.color(status)).frame(width: size, height: size)
    }
}

/// The website's status pill (dot, label, chevron) as a menu of the statuses. `small` is the 28pt one in rows.
struct StatusPill: View {
    let status: ListStatus
    let media: MediaKind
    var small = false
    var pick: (ListStatus) -> Void

    var body: some View {
        Menu {
            Picker("Status", selection: Binding(get: { status }, set: { pick($0) })) {
                ForEach(ListStatus.ordered) { s in
                    Text(s.label(media)).tag(s)
                }
            }
        } label: {
            StatusPillLabel(status: status, media: media, small: small)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Status: \(status.label(media))")
    }
}

/// the pill's look on its own (for places that aren't a menu)
struct StatusPillLabel: View {
    let status: ListStatus
    let media: MediaKind
    var small = false
    var chevron = true

    var body: some View {
        HStack(spacing: small ? 6 : 7) {
            StatusDot(status: status, size: small ? 7 : 8)
            Text(status.label(media))
                .font(.system(size: small ? 13 : 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            if chevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: small ? 10 : 11, weight: .bold))
                    .foregroundStyle(Theme.ink.opacity(0.55))
            }
        }
        .padding(.horizontal, small ? 10 : 12)
        .frame(height: small ? 28 : 34)
        .background(Theme.fill, in: Capsule())
        .fixedSize()
    }
}

// MARK: progress

/// − 6/11 + : a step back, the count, a step on
struct ProgressStepper: View {
    let progress: Int
    let total: Int?
    var small = false
    var minus: () -> Void
    var plus: () -> Void

    var body: some View {
        let side: CGFloat = small ? 30 : 34
        HStack(spacing: 0) {
            Button(action: minus) {
                Image(systemName: "minus").font(.system(size: small ? 12 : 14, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: side, height: side)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("One less")
            .disabled(progress <= 0)
            (Text(Format.grouped(progress)).foregroundStyle(Theme.ink)
                + Text(total.map { "/\(Format.grouped($0))" } ?? "").foregroundStyle(Theme.inkMuted).fontWeight(.medium))
                .font(.system(size: small ? 13 : 15, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: small ? 34 : 44)
            Button(action: plus) {
                Image(systemName: "plus").font(.system(size: small ? 12 : 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: side, height: side)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("One more")
            .disabled(total.map { progress >= $0 } ?? false)
        }
        .buttonStyle(.plain)
        .frame(height: side)
        .background(Theme.fill, in: Capsule())
        .fixedSize()
    }
}

/// a thin bar of how far along
struct ProgressBar: View {
    let fraction: Double
    var color: Color = Theme.progress
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color).frame(width: max(0, min(1, fraction)) * g.size.width)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// ★ 8.6
struct ScoreLabel: View {
    let value: String
    var size: CGFloat = 13
    var muted = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.system(size: size - 2)).foregroundStyle(Theme.star)
            Text(value).font(.system(size: size, weight: .semibold)).monospacedDigit()
                .foregroundStyle(muted ? Theme.inkSoft : Theme.ink)
        }
    }
}

// MARK: sections and rows

/// "Continue ›" with a sub line under it and something on the right ("7 in progress"). The title (with its
/// chevron) is a button when `action` is set.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var sub: String?
    var chevron = true
    var action: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    private var titleRow: some View {
        HStack(spacing: 3) {
            Text(title).font(.section).foregroundStyle(Theme.ink)
            if chevron && action != nil {
                Image(systemName: "chevron.right").font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.inkMuted)
            }
        }
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                // a disabled Button would grey the title, so a title without an action is plain text
                Group {
                    if let action {
                        Button(action: action) { titleRow }
                            .buttonStyle(.plain)
                    } else {
                        titleRow
                    }
                }
                .accessibilityAddTraits(.isHeader)
                if let sub {
                    Text(sub).font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, Theme.pad)
        .padding(.bottom, 12)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, sub: String? = nil, chevron: Bool = true, action: (() -> Void)? = nil) {
        self.init(title: title, sub: sub, chevron: chevron, action: action, trailing: { EmptyView() })
    }
}

/// the 0.5pt line between rows
struct Hairline: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle().fill(Theme.sep).frame(height: 0.5).padding(.leading, inset)
    }
}

/// A plain row (no grey cell): an optional square SF Symbol icon, the label with a sub line, a value and a chevron,
/// a hairline under it. Settings and forms use it; wrap it in a Button or NavigationLink to make it tappable.
struct PlainRow<Trailing: View>: View {
    let label: String
    var sub: String?
    var value: String?
    var symbol: String?
    var symbolColor: Color?
    var chevron = true
    var danger = false
    var separator = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(symbolColor ?? Theme.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 17)).foregroundStyle(danger ? Theme.danger : Theme.ink)
                    if let sub {
                        Text(sub).font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                    }
                }
                .padding(.vertical, 13)
                Spacer(minLength: 8)
                if let value {
                    Text(value).font(.system(size: 17)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                trailing()
                if chevron {
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            .padding(.trailing, Theme.pad)
            .frame(minHeight: 52)
            .overlay(alignment: .bottom) { if separator { Hairline() } }
        }
        .padding(.leading, Theme.pad)
        .contentShape(Rectangle())
    }
}

extension PlainRow where Trailing == EmptyView {
    init(_ label: String, sub: String? = nil, value: String? = nil, symbol: String? = nil, symbolColor: Color? = nil,
         chevron: Bool = true, danger: Bool = false, separator: Bool = true) {
        self.init(label: label, sub: sub, value: value, symbol: symbol, symbolColor: symbolColor, chevron: chevron,
                  danger: danger, separator: separator, trailing: { EmptyView() })
    }
}

/// rows under a small label (no ALL-CAPS), a hairline on top, an optional footer
struct RowGroup<Content: View>: View {
    var label: String?
    var footer: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label {
                Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, Theme.pad).padding(.bottom, 6)
            }
            Hairline()
            content()
            if let footer {
                Text(footer).font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, Theme.pad).padding(.top, 8)
            }
        }
        .padding(.bottom, 26)
    }
}

/// key–value details in two columns with hairlines
struct DetailsList: View {
    let pairs: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { i, p in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(p.0).foregroundStyle(Theme.inkMuted).frame(width: 118, alignment: .leading)
                    Text(p.1).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 15))
                .padding(.vertical, 11)
                .overlay(alignment: .bottom) { if i < pairs.count - 1 { Hairline() } }
            }
        }
        .padding(.horizontal, Theme.pad)
    }
}

/// a big number over a small label, in a row of columns (never a tile)
struct StatColumn: View {
    let value: String
    let label: String
    var size: CGFloat = 22
    var color: Color = Theme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: size, weight: .bold)).monospacedDigit().foregroundStyle(color)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// the five statuses as one thin bar (profile, stats)
struct StatusBar5: View {
    let counts: [ListStatus: Int]
    var height: CGFloat = 8

    var body: some View {
        let shown = ListStatus.ordered.filter { (counts[$0] ?? 0) > 0 }
        let total = max(1, shown.reduce(0) { $0 + (counts[$1] ?? 0) })
        GeometryReader { g in
            HStack(spacing: 2) {
                ForEach(shown) { s in
                    Theme.color(s)
                        .frame(width: max(3, (g.size.width - CGFloat(shown.count - 1) * 2) * CGFloat(counts[s] ?? 0) / CGFloat(total)))
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// a small genre/tag capsule
struct TagLabel: View {
    let text: String

    var body: some View {
        Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 11).frame(height: 28)
            .background(Theme.fill.opacity(0.8), in: Capsule())
    }
}

/// A filter chip. `on` marks an applied filter (brand tint); `menu` adds the chevron of a pull-down.
struct ChipLabel: View {
    let text: String
    var on = false
    var menu = false
    var symbol: String?
    var count: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 14, weight: .semibold)) }
            Text(text)
            if let count { Text(count).monospacedDigit().opacity(0.6) }
            if menu { Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).opacity(0.6) }
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(on ? Theme.brandSoft : Theme.ink)
        .padding(.leading, symbol == nil ? 14 : 11)
        .padding(.trailing, menu ? 11 : 14)
        .frame(height: 34)
        .background(on ? Theme.brand.opacity(0.18) : Theme.fill, in: Capsule())
        .overlay { if on { Capsule().strokeBorder(Theme.brand.opacity(0.4), lineWidth: 0.5) } }
    }
}

/// Text tabs under a title (a status filter, profile sections): the chosen one bold with a 2pt underline.
struct TextTabs<T: Hashable>: View {
    let items: [(T, String, Int?)]
    @Binding var selection: T

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(items, id: \.0) { item in
                    Button {
                        selection = item.0
                    } label: {
                        HStack(spacing: 4) {
                            Text(item.1).fontWeight(item.0 == selection ? .semibold : .medium)
                                .foregroundStyle(item.0 == selection ? Theme.ink : Theme.inkMuted)
                            if let n = item.2 {
                                Text(Format.grouped(n)).monospacedDigit().foregroundStyle(Theme.inkMuted)
                            }
                        }
                        .font(.system(size: 15))
                        .padding(.bottom, 9)
                        .overlay(alignment: .bottom) {
                            if item.0 == selection { Rectangle().fill(Theme.ink).frame(height: 2) }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(item.0 == selection ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.pad)
        }
    }
}

/// A short paragraph cut to a few lines, with More to open it.
struct MoreText: View {
    let text: String
    var lines = 4
    var size: CGFloat = 15
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(.system(size: size)).foregroundStyle(Theme.inkSoft)
                .lineSpacing(size * 0.25)
                .lineLimit(open ? nil : lines)
            if !open {
                Button("More") { open = true }
                    .font(.system(size: size, weight: .semibold)).foregroundStyle(Theme.brandSoft)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.pad)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: buttons

/// The kit's capsule buttons: tint (filled brand), tone (grey), white (on art), plain (brand text).
/// Glass buttons are only the system's own (toolbar items, `.buttonStyle(.glass)` in bars), never on content.
struct CapsuleButtonStyle: ButtonStyle {
    enum Kind { case tint, tone, white, plain }
    enum Size { case small, regular, large }

    var kind: Kind = .tone
    var size: Size = .regular
    var color: Color?
    var full = false

    func makeBody(configuration: Configuration) -> some View {
        let h: CGFloat = size == .large ? 52 : size == .small ? 32 : 44
        let fs: CGFloat = size == .large ? 17 : size == .small ? 14 : 16
        configuration.label
            .font(.system(size: fs, weight: .semibold))
            .labelStyle(TightLabelStyle())
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .foregroundStyle(foreground)
            // full-width buttons share a row, so they keep less to the side
            .padding(.horizontal, full ? 8 : size == .small ? 13 : 18)
            .frame(maxWidth: full ? .infinity : nil)
            .frame(height: h)
            .background(background, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }

    private var foreground: Color {
        switch kind {
        case .tint: return .white
        case .tone: return color ?? Theme.ink
        case .white: return .black
        case .plain: return color ?? Theme.brandSoft
        }
    }

    private var background: Color {
        switch kind {
        case .tint: return Theme.brand
        case .tone: return Theme.fill
        case .white: return Theme.ink
        case .plain: return .clear
        }
    }
}

/// icon and title 7pt apart, as the kit's buttons have them
struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon
            configuration.title
        }
    }
}

extension ButtonStyle where Self == CapsuleButtonStyle {
    static func capsule(_ kind: CapsuleButtonStyle.Kind = .tone, _ size: CapsuleButtonStyle.Size = .regular,
                        color: Color? = nil, full: Bool = false) -> CapsuleButtonStyle {
        CapsuleButtonStyle(kind: kind, size: size, color: color, full: full)
    }
}

// MARK: loading a page

/// One page's data: a spinner while it comes, a plain message if it doesn't, the page when it's here. Loads once
/// (pull to refresh loads again); `id` reloads when it changes.
struct PageLoader<T, Content: View>: View {
    var id: String = ""
    let load: (APIClient) async throws -> T
    @ViewBuilder let content: (T) -> Content

    @Environment(AppModel.self) private var model
    @State private var state: Load<T> = .loading
    @State private var loadedID: String?

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let why):
                ContentUnavailableView {
                    Label("Couldn't load this", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(why)
                } actions: {
                    Button("Try again") { Task { await reload() } }.buttonStyle(.capsule(.tone, .small))
                }
            case .loaded(let value):
                content(value)
            }
        }
        .task(id: id) {
            guard loadedID != id || state.value == nil else { return }
            await reload()
        }
        .refreshable { await reload() }
    }

    private func reload() async {
        let next = await model.fetch(load)
        state = next
        loadedID = id
    }
}

// MARK: little helpers

extension View {
    /// a section's spacing under the one before
    func sectionGap(_ h: CGFloat = 30) -> some View { padding(.top, h) }
}

/// the website's scores: 85 -> "8.5"
func scoreText(_ score: Int?) -> String? { score.map { Format.score10($0) } }
