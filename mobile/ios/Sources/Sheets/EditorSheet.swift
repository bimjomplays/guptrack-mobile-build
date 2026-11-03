import SwiftUI

/// The list editor over a title page (18 at its short height, 19 pulled up to large). It edits a draft of the entry;
/// ✓ saves it with one `model.change`, ✕ drops it. Short: status, the big − 6 / 11 +, the 10-point score, favourite.
/// Large: the compact stepper, then favourite, volume (manga), rewatches, dates, the note, review and remove.
struct EditorSheet: View {
    let titleId: String
    var expanded = false

    /// the short detent's height (the mockup's sheet is 488pt tall)
    static let short = PresentationDetent.height(500)

    @State private var detent: PresentationDetent

    init(titleId: String, expanded: Bool = false) {
        self.titleId = titleId
        self.expanded = expanded
        _detent = State(initialValue: expanded ? .large : EditorSheet.short)
    }

    var body: some View {
        SheetTitleLoader(titleId: titleId) { title, entry in
            EditorForm(draft: entry.map { TitleSheets.EditorDraft(entry: $0) } ?? TitleSheets.EditorDraft(title: title),
                       large: detent == .large)
        }
        .presentationDetents([EditorSheet.short, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }
}

private struct EditorForm: View {
    @State var draft: TitleSheets.EditorDraft
    let large: Bool

    @Environment(AppModel.self) private var model
    @State private var confirmRemove = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    statusSection
                    if draft.hasProgress {
                        progressSection.padding(.top, large ? 20 : 24)
                    }
                    scoreSection.padding(.top, large ? 20 : 24)
                    if large {
                        moreRows.padding(.top, 16)
                    } else {
                        favouriteRow.padding(.top, 20)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(draft.title.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { bar }
            .confirmationDialog("Remove \(draft.title.name) from your list?", isPresented: $confirmRemove,
                                titleVisibility: .visible) {
                Button("Remove from list", role: .destructive) { remove() }
            }
        }
    }

    // MARK: the bar

    @ToolbarContentBuilder
    private var bar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .cancel) { model.sheet = nil }
                .accessibilityLabel("Cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(role: .confirm) { save() }
                .accessibilityLabel("Save")
        }
    }

    private func save() {
        model.sheet = nil
        draft.save(to: model)
    }

    private func remove() {
        model.sheet = nil
        draft.remove(from: model)
    }

    // MARK: sections

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetEditLabel("Status")
            SheetStatusChoices(status: draft.status, media: draft.media) { draft.setStatus($0) }
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if large {
                SheetEditLabel("Progress")
                compactProgress
            } else {
                SheetEditLabel(text: "Progress") {
                    if let next = draft.nextLine {
                        Text(next).font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                    }
                }
                bigProgress
            }
        }
    }

    /// − [6 / 11, Episode 6 of 11] + (the short sheet)
    private var bigProgress: some View {
        HStack {
            SheetRoundStep(symbol: "minus", label: "One less \(draft.media.unit ?? "")",
                           enabled: draft.canStepDown) { draft.step(-1) }
            Spacer(minLength: 8)
            VStack(spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(Format.grouped(draft.progress)).font(.system(size: 38, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    if let total = draft.total {
                        Text(" / \(Format.grouped(total))").font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                .monospacedDigit()
                Text(draft.progressCaption).font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            SheetRoundStep(symbol: "plus", strong: true, label: "One more \(draft.media.unit ?? "")",
                           enabled: draft.canStepUp) { draft.step(1) }
        }
        .padding(.horizontal, Theme.pad)
    }

    /// Episode 6 of 11 ……… − 6/11 + (the large sheet)
    private var compactProgress: some View {
        HStack {
            progressWords
            Spacer(minLength: 8)
            ProgressStepper(progress: draft.progress, total: draft.total,
                            minus: { draft.step(-1) }, plus: { draft.step(1) })
        }
        .padding(.horizontal, Theme.pad)
    }

    private var progressWords: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(draft.unitWord + " ").foregroundStyle(Theme.ink)
            Text(Format.grouped(draft.progress)).fontWeight(.bold).foregroundStyle(Theme.ink)
            if let total = draft.total {
                Text(" of \(Format.grouped(total))").foregroundStyle(Theme.inkMuted)
            }
        }
        .font(.system(size: 17))
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetEditLabel(text: "Your score") { scoreTrailing }
            SheetScoreRow(chosen: draft.scoreDot) { draft.pickScore($0) }
        }
    }

    @ViewBuilder
    private var scoreTrailing: some View {
        if large {
            Text("10 point").font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
        } else if let s = draft.scoreText {
            HStack(spacing: 4) {
                Image(systemName: "star.fill").font(.system(size: 13)).foregroundStyle(Theme.star)
                Text(s).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("/ 10").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.inkMuted)
            }
            .monospacedDigit()
        } else {
            Text("Not scored").font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
        }
    }

    /// ♡ Favourite with its switch (the short sheet)
    private var favouriteRow: some View {
        HStack(spacing: 12) {
            Image(systemName: draft.favourite ? "heart.fill" : "heart").font(.system(size: 19, weight: .medium))
                .foregroundStyle(draft.favourite ? Color(hex: 0xFF375F) : Theme.inkSoft)
            Toggle("Favourite", isOn: $draft.favourite).font(.system(size: 17)).foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, Theme.pad)
        .frame(height: 52)
        .overlay(alignment: .top) { Hairline() }
    }

    // MARK: the large sheet's rows

    private var moreRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            PlainRow(label: "Favourite", chevron: false) {
                Toggle("Favourite", isOn: $draft.favourite).labelsHidden()
            }
            if draft.media == .manga {
                PlainRow(label: "Volume", chevron: false) {
                    ProgressStepper(progress: draft.volume ?? 0, total: draft.title.volumes, small: true,
                                    minus: { draft.stepVolume(-1) }, plus: { draft.stepVolume(1) })
                }
            }
            PlainRow(label: draft.media.isReading ? "Rereads" : "Rewatches", chevron: false) {
                ProgressStepper(progress: draft.repeats, total: nil, small: true,
                                minus: { draft.stepRepeats(-1) }, plus: { draft.stepRepeats(1) })
            }
            PlainRow(label: "Started", chevron: false) { dateField($draft.started) }
            PlainRow(label: "Finished", chevron: false) { dateField($draft.finished) }
            noteField.padding(.top, 14)
            reviewRow.padding(.top, 6)
            if !draft.isNew {
                removeButton.padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private func dateField(_ day: Binding<String?>) -> some View {
        if let current = day.wrappedValue, let date = Format.parseDay(current) {
            DatePicker("", selection: Binding(get: { date }, set: { day.wrappedValue = Format.day($0) }),
                       in: ...Clock.now, displayedComponents: .date)
                .labelsHidden()
                .contextMenu {
                    Button("Clear date", systemImage: "xmark.circle", role: .destructive) { day.wrappedValue = nil }
                }
        } else {
            Button("Add date") { day.wrappedValue = Format.day(Clock.now) }
                .font(.system(size: 17))
                .foregroundStyle(Theme.brandSoft)
                .buttonStyle(.plain)
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
            TextField("A note, shown with this list", text: $draft.notes, axis: .vertical)
                .font(.system(size: 16))
                .lineLimit(2...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(minHeight: 66, alignment: .topLeading)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.sep, lineWidth: 0.5))
        }
        .padding(.horizontal, Theme.pad)
    }

    private var reviewRow: some View {
        Button {
            // the edits so far are kept: going on to write a review means keeping them
            let id = draft.title.id
            draft.save(to: model)
            model.sheet = .writeReview(id)
        } label: {
            PlainRow("Review", value: "Write a review", separator: false)
        }
        .buttonStyle(.plain)
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            confirmRemove = true
        } label: {
            Label("Remove from list", systemImage: "trash")
        }
        .buttonStyle(.capsule(.tone, color: Theme.danger, full: true))
        .padding(.horizontal, Theme.pad)
    }
}
