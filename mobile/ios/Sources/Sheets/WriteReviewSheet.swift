import SwiftUI

/// Write a review (27): a full-height sheet with the title on top, your score, the review, a spoiler switch and who
/// can see it; Post in the bar. A changed score is saved to your list too.
struct WriteReviewSheet: View {
    let titleId: String

    var body: some View {
        SheetTitleLoader(titleId: titleId) { title, entry in
            ReviewForm(title: title, entry: entry, draft: TitleSheets.ReviewDraft(score: entry?.score))
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct ReviewForm: View {
    let title: Title
    let entry: LibraryEntry?
    @State var draft: TitleSheets.ReviewDraft

    @Environment(AppModel.self) private var model
    @State private var posting = false
    @FocusState private var writing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    titleRow
                    SheetEditLabel(text: "Your score") {
                        Text(draft.scoreText ?? "Not scored").font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                            .monospacedDigit()
                    }
                    SheetScoreRow(chosen: TitleSheets.scoreDot(draft.score)) { draft.pickScore($0) }
                    textArea
                    spoilerRow.padding(.top, 12)
                    footerRow.padding(.top, 10)
                }
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { model.sheet = nil }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post", role: .confirm) { post() }
                        .disabled(!draft.canPost || posting)
                }
            }
        }
        .task { writing = true }
    }

    private var titleRow: some View {
        let line = TitleSheets.reviewLine(title, entry: entry)
        return HStack(spacing: 14) {
            Poster(url: title.cover, width: 44, ratio: 64.0 / 44.0, radius: 6, flat: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                HStack(spacing: 0) {
                    Text(line.kind)
                    if let s = line.status {
                        Text(" · ")
                        Text(s.label(title.media)).foregroundStyle(Theme.color(s))
                    }
                    if let p = line.progress { Text(" · " + p) }
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.bottom, 16)
        .accessibilityElement(children: .combine)
    }

    private var textArea: some View {
        TextEditor(text: $draft.text)
            .font(.system(size: 17))
            .foregroundStyle(Theme.ink)
            .scrollContentBackground(.hidden)
            .focused($writing)
            .frame(minHeight: 136)
            .overlay(alignment: .topLeading) {
                if draft.text.isEmpty {
                    Text("What did you think?").font(.system(size: 17)).foregroundStyle(Theme.inkFaint)
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Review text")
            .padding(.top, 10)
            .overlay(alignment: .top) { Hairline() }
            .padding(.horizontal, Theme.pad - 5)
            .padding(.top, 16)
    }

    private var spoilerRow: some View {
        Toggle(isOn: $draft.spoilers) {
            HStack(spacing: 8) {
                Image(systemName: "eye.slash").font(.system(size: 15, weight: .medium))
                Text("Contains spoilers")
            }
            .font(.system(size: 15))
            .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, Theme.pad)
    }

    private var footerRow: some View {
        HStack {
            Menu {
                Picker("Who can see it", selection: $draft.visibility) {
                    ForEach(Visibility.allCases) { v in
                        Label(v.label, systemImage: v.symbol).tag(v)
                    }
                }
            } label: {
                ChipLabel(text: draft.visibility.label, menu: true, symbol: draft.visibility.symbol)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Who can see it: \(draft.visibility.label)")
            Spacer(minLength: 8)
            Text(draft.countText).font(.system(size: 13)).monospacedDigit()
                .foregroundStyle(draft.tooLong ? Theme.danger : Theme.inkFaint)
        }
        .padding(.horizontal, Theme.pad)
    }

    private func post() {
        let body = draft.body
        let score = draft.score
        let id = title.id
        posting = true
        Task {
            let r: Load<OKReply> = await model.fetch { try await $0.sheetPostReview(id, body) }
            posting = false
            if let why = r.error {
                model.notice = "Couldn't post your review: \(why)"
                return
            }
            if let e = entry, e.score != score {
                model.change(id, LibraryPatch(score: score ?? -1))
            }
            model.sheet = nil
        }
    }
}
