import SwiftUI

// Share to GupTrack (66): the sheet the share extension shows for a shared link or text. Plain SwiftUI with its own
// colours (the app's Theme isn't in the extension); the app compiles this file too, so the screen tests can draw it.
// The matching is ShareMatch (GupTrackKit, tested on Linux); pictures come through `art` (AsyncImage in the
// extension, the app's Artwork in the tests).

/// the colours the share sheet uses
enum ShareInk {
    static let brand = Color(red: 10 / 255, green: 132 / 255, blue: 1)
    static let ink = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let muted = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.55)
    static let sep = Color(red: 84 / 255, green: 84 / 255, blue: 88 / 255).opacity(0.55)
    static let fill = Color(red: 118 / 255, green: 118 / 255, blue: 128 / 255).opacity(0.22)
    static let keyline = Color.white.opacity(0.08)
    static let sheet = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)

    /// a status's colour from its hex ("#30d158")
    static func status(_ s: ListStatus) -> Color {
        let v = UInt32(s.hex.dropFirst(), radix: 16) ?? 0x8E8E93
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}

struct ShareSheetView<Art: View>: View {
    let found: ShareMatch.Found?
    /// the matched title's season lengths (TV)
    let seasons: [Int]?
    let art: (URL?) -> Art
    var onAdd: (ShareMatch.Draft) -> Void
    var onCancel: () -> Void

    @State private var draft: ShareMatch.Draft

    init(found: ShareMatch.Found?, seasons: [Int]?, art: @escaping (URL?) -> Art,
         onAdd: @escaping (ShareMatch.Draft) -> Void, onCancel: @escaping () -> Void) {
        self.found = found
        self.seasons = seasons
        self.art = art
        self.onAdd = onAdd
        self.onCancel = onCancel
        _draft = State(initialValue: found.map { ShareMatch.Draft($0) } ?? ShareMatch.Draft(status: .planned, progress: 0))
    }

    var body: some View {
        NavigationStack {
            page
                .navigationTitle("Add to GupTrack")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel, action: onCancel)
                    }
                }
        }
    }

    @ViewBuilder private var page: some View {
        if let found {
            VStack(spacing: 0) {
                ScrollView {
                    ShareSheetContent(found: found, seasons: seasons, art: art, draft: $draft)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                addButton(found)
            }
            .background(ShareInk.sheet)
        } else {
            ContentUnavailableView("No title found", systemImage: "link",
                                   description: Text("GupTrack couldn't match what you shared to a title."))
                .background(ShareInk.sheet)
        }
    }

    private func addButton(_ found: ShareMatch.Found) -> some View {
        Button {
            onAdd(draft)
        } label: {
            Text(ShareMatch.addLabel(found))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(ShareInk.brand, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

/// the match, the status chips and the progress row
struct ShareSheetContent<Art: View>: View {
    let found: ShareMatch.Found
    let seasons: [Int]?
    let art: (URL?) -> Art
    @Binding var draft: ShareMatch.Draft

    private var title: Title { found.title }
    private var stepper: ShareMatch.Stepper? { ShareMatch.stepper(title, progress: draft.progress, seasons: seasons) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let link = found.link {
                Label(link, systemImage: "link")
                    .labelStyle(ShareTightLabel(spacing: 8))
                    .font(.system(size: 13))
                    .foregroundStyle(ShareInk.muted)
                    .lineLimit(1)
                    .padding(.bottom, 14)
            }
            match
            Text("Status")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ShareInk.muted)
                .padding(.top, 22)
                .padding(.bottom, 10)
            ShareFlow(spacing: 8) {
                ForEach(ShareMatch.statuses) { s in
                    ShareStatusChip(status: s, media: title.media, on: draft.status == s) {
                        draft.choose(s, max: stepper?.max)
                    }
                }
            }
            if let stepper {
                progressRow(stepper)
            }
        }
    }

    private var match: some View {
        HStack(spacing: 14) {
            art(title.cover)
                .frame(width: 64, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(ShareInk.keyline, lineWidth: 1))
            VStack(alignment: .leading, spacing: 0) {
                Text(title.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(ShareInk.ink)
                    .lineLimit(2)
                Text(ShareMatch.caption(title, seasons: seasons))
                    .font(.system(size: 14))
                    .foregroundStyle(ShareInk.muted)
                    .padding(.top, 2)
                Label(found.how == .link ? "Matched from the link" : "Best match for what you shared",
                      systemImage: found.how == .link ? "checkmark.circle" : "magnifyingglass")
                    .labelStyle(ShareTightLabel(spacing: 5))
                    .font(.system(size: 13))
                    .foregroundStyle(found.how == .link ? ShareInk.status(.current) : ShareInk.muted)
                    .padding(.top, 7)
            }
            Spacer(minLength: 0)
        }
    }

    private func progressRow(_ s: ShareMatch.Stepper) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Progress").font(.system(size: 17)).foregroundStyle(ShareInk.ink)
                if let note = s.note {
                    Text(note).font(.system(size: 13)).monospacedDigit().foregroundStyle(ShareInk.muted)
                }
            }
            Spacer()
            ShareStepper(value: s.value, total: s.total, canMinus: draft.progress > 0,
                         canPlus: s.max.map { draft.progress < $0 } ?? true,
                         minus: { draft.step(-1, media: title.media, max: s.max) },
                         plus: { draft.step(1, media: title.media, max: s.max) })
        }
        .padding(.top, 14)
        .overlay(alignment: .top) { Rectangle().fill(ShareInk.sep).frame(height: 0.5) }
        .padding(.top, 22)
    }
}

/// a status choice: dot and words in a capsule, the chosen one tinted in its colour
struct ShareStatusChip: View {
    let status: ListStatus
    let media: MediaKind
    let on: Bool
    let action: () -> Void

    var body: some View {
        let color = ShareInk.status(status)
        Button(action: action) {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(status.label(media))
                    .font(.system(size: 15, weight: on ? .semibold : .medium))
                    .foregroundStyle(ShareInk.ink)
            }
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(on ? color.opacity(0.16) : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? color.opacity(0.5) : Color.white.opacity(0.18), lineWidth: on ? 1 : 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status.label(media))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// − 6/10 +
struct ShareStepper: View {
    let value: Int
    let total: Int?
    let canMinus: Bool
    let canPlus: Bool
    var minus: () -> Void
    var plus: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: minus) {
                Image(systemName: "minus").font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 38).contentShape(Rectangle())
            }
            .accessibilityLabel("One less")
            .disabled(!canMinus)
            (Text(Format.grouped(value)).foregroundStyle(ShareInk.ink)
                + Text(total.map { "/\(Format.grouped($0))" } ?? "").foregroundStyle(ShareInk.muted))
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 52)
            Button(action: plus) {
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 38).contentShape(Rectangle())
            }
            .accessibilityLabel("One more")
            .disabled(!canPlus)
        }
        .foregroundStyle(ShareInk.ink)
        .buttonStyle(.plain)
        .background(ShareInk.fill, in: Capsule())
        .fixedSize()
    }
}

/// a Label with the icon closer to the words
struct ShareTightLabel: LabelStyle {
    var spacing: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

/// lays the status chips out in rows, wrapping when a row is full
struct ShareFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var row: CGFloat = 0
        var widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += row + spacing
                row = 0
            }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += row + spacing
                row = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
