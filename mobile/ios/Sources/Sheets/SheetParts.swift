import SwiftUI

// Parts the title sheets share (18, 19, 26, 27, 53): the title a sheet is about, the small labels, the status
// choices, the 10-point score row and a wrapping layout. Drawn after design/iphone/screens/_titles2.mjs.

/// The title a sheet is about: from your list when it's there, else loaded from its title page.
struct SheetTitleLoader<Content: View>: View {
    let titleId: String
    @ViewBuilder let content: (Title, LibraryEntry?) -> Content

    @Environment(AppModel.self) private var model

    var body: some View {
        if let e = model.entry(titleId) {
            content(e.title, e)
        } else {
            PageLoader(id: titleId, load: { try await $0.sheetTitle(titleId) }) { t in
                content(t, nil)
            }
        }
    }
}

/// a sheet's small muted label ("Status", "Your score") with something on the right
struct SheetEditLabel<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, Theme.pad)
        .padding(.bottom, 9)
    }
}

extension SheetEditLabel where Trailing == EmptyView {
    init(_ text: String) {
        self.init(text: text, trailing: { EmptyView() })
    }
}

/// The five statuses as wrapping capsules with their dots; the chosen one tinted with its colour.
struct SheetStatusChoices: View {
    let status: ListStatus
    let media: MediaKind
    var pick: (ListStatus) -> Void

    var body: some View {
        SheetFlow(spacing: 8) {
            ForEach(ListStatus.ordered) { s in
                choice(s)
            }
        }
        .padding(.horizontal, Theme.pad)
    }

    private func choice(_ s: ListStatus) -> some View {
        let on = s == status || (s == .current && status == .repeating)
        let color = Theme.color(s)
        return Button {
            pick(s)
        } label: {
            HStack(spacing: 7) {
                StatusDot(status: s, size: 8)
                Text(s.label(media)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(on ? Theme.ink : Theme.inkSoft)
            }
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(on ? color.opacity(0.16) : Theme.fill, in: Capsule())
            .overlay { if on { Capsule().strokeBorder(color, lineWidth: 1) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The 10-point score row: ten round buttons, the chosen one filled yellow, the ones under it tinted.
struct SheetScoreRow: View {
    /// 1-10, nil when unscored
    let chosen: Int?
    var pick: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...10, id: \.self) { n in
                if n > 1 { Spacer(minLength: 2) }
                dot(n)
            }
        }
        .padding(.horizontal, Theme.pad)
    }

    private func dot(_ n: Int) -> some View {
        let on = n == chosen
        let below = (chosen ?? 0) > n
        let fill: Color = on ? Theme.star : below ? Theme.star.opacity(0.16) : Theme.fill
        let ink: Color = on ? .black : below ? Theme.star : Theme.inkSoft
        return Button {
            pick(n)
        } label: {
            Text("\(n)").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                .foregroundStyle(ink)
                .frame(width: 31, height: 31)
                .background(fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Score \(n)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Lays its children out in rows, wrapping to the next row when one is full (the status choices).
struct SheetFlow: Layout {
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

/// a round 52pt − or + (the editor's big progress control)
struct SheetRoundStep: View {
    let symbol: String
    var strong = false
    let label: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 52, height: 52)
                .background(strong ? Theme.fillStrong : Theme.fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }
}
