import SwiftUI

/// Compare lists (49): you and someone else for one media. In common, scored by both, how far apart on average;
/// then Most different / Best together with both scores side by side. The toolbar switches the media. One call
/// (GET users/:username/compare) brings every media; the switch only picks which part is shown.
struct CompareView: View {
    let username: String

    @State private var media: MediaKind = .anime

    var body: some View {
        PageLoader(id: username, load: { try await $0.compare(username) }) { c in
            CompareContent(person: c.person, result: c.on(media))
        }
        .pageBackground()
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Media", selection: $media) {
                        ForEach(MediaKind.allCases) { m in Label(m.plural, systemImage: m.symbol).tag(m) }
                    }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .accessibilityLabel("Media")
            }
        }
    }
}

private struct CompareContent: View {
    let person: Person
    let result: CompareSet

    @Environment(AppModel.self) private var model
    @State private var best = false

    var body: some View {
        let rows = best ? result.bestTogether : result.mostDifferent
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                head
                Picker("Order", selection: $best) {
                    Text("Most different").tag(false)
                    Text("Best together").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.pad)
                .padding(.top, 16)
                if rows.isEmpty {
                    ContentUnavailableView("Nothing scored by both", systemImage: "star.leadinghalf.filled",
                                           description: Text("Titles you have both scored show up here."))
                        .padding(.top, 30)
                } else {
                    columnHead
                    ForEach(Array(rows.prefix(25).enumerated()), id: \.element.id) { i, r in
                        NavigationLink(value: Route.title(r.titleId)) {
                            CompareRow(row: r, separator: i < min(rows.count, 25) - 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
    }

    private var head: some View {
        VStack(spacing: 0) {
            HStack(spacing: -12) {
                Avatar(url: model.account?.user.avatar, size: 64)
                    .padding(3).background(Theme.sheet, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                Avatar(url: person.avatar, size: 64)
                    .padding(3).background(Theme.sheet, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            Text("You and \(person.username)").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.ink)
                .padding(.top, 9)
            Text(result.subtitle).font(.system(size: 14)).foregroundStyle(Theme.inkMuted).padding(.top, 2)
            HStack(alignment: .top, spacing: 10) {
                StatColumn(value: Format.grouped(result.inCommon), label: "In common", size: 26)
                StatColumn(value: Format.grouped(result.scoredByBoth), label: "Scored by both", size: 26)
                StatColumn(value: result.apartText, label: "Apart on average", size: 26)
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, 24)
            .padding(.bottom, 18)
            .overlay(alignment: .bottom) { Hairline() }
        }
        .frame(maxWidth: .infinity)
    }

    private var columnHead: some View {
        HStack(spacing: 16) {
            Spacer()
            Text("You").frame(width: 40)
            Text(person.username).lineLimit(1).minimumScaleFactor(0.7).frame(width: 40)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Theme.inkMuted)
        .padding(.horizontal, Theme.pad)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }
}

/// a title with how far apart you are and both scores
private struct CompareRow: View {
    let row: ComparedTitle
    var separator = true

    var body: some View {
        HStack(spacing: 14) {
            Poster(url: row.card.cover, width: 42, radius: 6, flat: true).padding(.vertical, 9)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(row.caption).font(.system(size: 13)).foregroundStyle(Theme.inkMuted).numbers()
                }
                Spacer(minLength: 0)
                HStack(spacing: 16) {
                    score(row.myScore)
                    score(row.theirScore)
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) { if separator { Hairline() } }
        }
        .padding(.horizontal, Theme.pad)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func score(_ v: Int?) -> some View {
        Group {
            if let s = scoreText(v) { ScoreLabel(value: s, size: 15) } else { Text("–").foregroundStyle(Theme.inkMuted) }
        }
        .frame(width: 40)
    }
}
