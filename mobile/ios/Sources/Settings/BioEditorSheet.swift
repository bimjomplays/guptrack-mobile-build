import SwiftUI

/// The bio editor (57): a full-height sheet. Write (markdown, with lists from your library as cards) and Preview,
/// swiped between on iPhone; the website's bio presets (their look); a formatting bar with Insert list. Parts the
/// phone can't edit (pictures, columns, sections) stay as they are, as cards you can remove.
struct BioEditorSheet: View {
    @Environment(AppModel.self) private var model
    @State private var style = AccountSettingsStore.shared.settings?.bio.style ?? .standard
    @State private var doc = BioDocument(doc: AccountSettingsStore.shared.settings?.bio.doc ?? BioState.emptyDoc)
    @State private var mode = 0
    @FocusState private var focused: Int?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    Text("Write").tag(0)
                    Text("Preview").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.pad)
                .padding(.bottom, 14)
                presets
                TabView(selection: $mode) {
                    writer.tag(0)
                    BioPreview(doc: doc, style: style).tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .overlay(alignment: .top) { Hairline() }
                .padding(.top, 12)
            }
            .background(Theme.sheet)
            .navigationTitle("Edit bio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { model.sheet = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { save() }
                }
                ToolbarItemGroup(placement: .bottomBar) { formatBar }
            }
        }
        .presentationDetents([.large])
        .task { await loadSettings() }
    }

    /// opened straight from a link: the settings may not be here yet
    private func loadSettings() async {
        let store = AccountSettingsStore.shared
        guard store.needsLoad(for: model.account?.user.username) else { return }
        guard case .loaded(let s) = await model.fetch({ try await $0.accountSettings() }) else { return }
        store.loaded(s, for: model.account?.user.username)
        style = s.bio.style
        doc = BioDocument(doc: s.bio.doc)
    }

    private var presets: some View {
        let picked = BioPreset.matching(style)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Presets").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .padding(.trailing, 2)
                ForEach(BioPreset.allCases) { p in
                    Button(p.label) { style = p.style }
                        .buttonStyle(.capsule(p == picked ? .tint : .tone, .small))
                        .accessibilityAddTraits(p == picked ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.pad)
        }
    }

    // MARK: write

    private var writer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(doc.blocks.enumerated()), id: \.offset) { i, block in
                    switch block {
                    case .text: textBlock(i)
                    case .list(let l): listCard(i, l)
                    case .kept(let n): keptCard(i, n)
                    }
                }
                Text("Markdown works here. On iPhone, swipe between Write and Preview; pictures and columns are added on the website.")
                    .font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, Theme.pad).padding(.top, 18)
            }
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func textBlock(_ i: Int) -> some View {
        TextField("Write about yourself", text: textBinding(i), axis: .vertical)
            .font(.system(size: 15, design: .monospaced))
            .lineSpacing(5)
            .foregroundStyle(Theme.ink)
            .focused($focused, equals: i)
            .padding(.horizontal, Theme.pad)
            .padding(.vertical, 4)
    }

    private func textBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: {
                guard doc.blocks.indices.contains(i), case .text(let s) = doc.blocks[i] else { return "" }
                return s
            },
            set: { v in if doc.blocks.indices.contains(i) { doc.blocks[i] = .text(v) } }
        )
    }

    private func listCard(_ i: Int, _ l: BioList) -> some View {
        let caption = l.showsTitles
            ? SettingsText.titles(l.titles(model.library).count) + " · " + (l.showsCovers ? "Covers" : "List")
            : "Set up on the website"
        return BlockCard(symbol: "list.bullet.rectangle", title: l.heading, caption: caption) {
            if l.showsTitles {
                Button("Show covers", systemImage: "square.grid.2x2") { relayout(i, "grid") }
                Button("Show as a list", systemImage: "list.bullet") { relayout(i, "list") }
            }
            Button("Remove", systemImage: "trash", role: .destructive) { doc.remove(at: i) }
        }
    }

    private func keptCard(_ i: Int, _ n: JSONValue) -> some View {
        BlockCard(symbol: "square.on.square", title: BioDocument.keptLabel(n), caption: "Kept as it is · edit it on the website") {
            Button("Remove", systemImage: "trash", role: .destructive) { doc.remove(at: i) }
        }
    }

    private func relayout(_ i: Int, _ layout: String) {
        guard doc.blocks.indices.contains(i), case .list(var l) = doc.blocks[i] else { return }
        l.attrs["layout"] = .string(layout)
        doc.blocks[i] = .list(l)
    }

    // MARK: the formatting bar

    @ViewBuilder private var formatBar: some View {
        ForEach(BioDocument.Style.allCases, id: \.self) { s in
            Button { format(s) } label: { Image(systemName: s.symbol) }
                .accessibilityLabel(s.label)
        }
        Spacer()
        insertMenu
    }

    private var insertMenu: some View {
        Menu {
            ForEach(BioList.titleSources, id: \.0) { source in
                Menu(source.1) {
                    Button("Everything") { insert(source.0, nil) }
                    ForEach(APIMedia.allCases, id: \.self) { m in
                        Button(m.kind.plural) { insert(source.0, m) }
                    }
                }
            }
        } label: {
            Label("Insert list", systemImage: "text.badge.plus").labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.brand)
    }

    /// the text block being edited, else the last one
    private var target: Int? {
        if let focused, doc.blocks.indices.contains(focused), case .text = doc.blocks[focused] { return focused }
        return doc.blocks.indices.last { if case .text = doc.blocks[$0] { return true } else { return false } }
    }

    private func format(_ s: BioDocument.Style) {
        guard let i = target, case .text(let text) = doc.blocks[i] else { return }
        doc.blocks[i] = .text(s.apply(text))
        focused = i
    }

    private func insert(_ source: String, _ media: APIMedia?) {
        doc.insert(BioList.make(source: source, media: media), after: target)
    }

    private func save() {
        let s = style
        let d = doc.doc
        model.editSettings(delay: 0) {
            $0.bio.style = s
            $0.bio.doc = d
        }
        model.sheet = nil
    }
}

/// a list or a kept part of the bio in the writer: what it is, and a menu
private struct BlockCard<Actions: View>: View {
    let symbol: String
    let title: String
    let caption: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(Theme.brandSoft)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(caption).font(.system(size: 12.5)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 0)
            Menu { actions() } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(title) options")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.brand.opacity(0.35), lineWidth: 0.5))
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, 6)
    }
}

/// the bio as the profile shows it, in its style's type (system faces standing in for the website's fonts)
private struct BioPreview: View {
    let doc: BioDocument
    let style: BioStyle

    @Environment(AppModel.self) private var model

    static func design(_ font: String) -> Font.Design {
        switch font {
        case "lora", "fraunces", "playfair": return .serif
        case "jetbrains": return .monospaced
        case "caveat": return .rounded
        default: return .default
        }
    }

    private var size: CGFloat { style.size == "s" ? 15 : style.size == "l" ? 17.5 : 16 }
    private var center: Bool { style.align == "center" }

    var body: some View {
        ScrollView {
            VStack(alignment: center ? .center : .leading, spacing: style.spacing == "tight" ? 4 : style.spacing == "airy" ? 9 : 6) {
                ForEach(Array(doc.blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let s):
                        ForEach(Array(BioDocument.lines(s).enumerated()), id: \.offset) { _, line in
                            BioLineView(line: line, text: Self.design(style.bodyFont),
                                        heading: Self.design(style.headingFont), size: size)
                        }
                    case .list(let l):
                        BioListPreview(list: l, titles: l.titles(model.library))
                    case .kept(let n):
                        Text(BioDocument.keptLabel(n)).font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            .multilineTextAlignment(center ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: center ? .center : .leading)
            .padding(.horizontal, Theme.pad)
            .padding(.vertical, 16)
        }
    }
}

private struct BioLineView: View {
    let line: BioDocument.Line
    let text: Font.Design
    let heading: Font.Design
    let size: CGFloat

    var body: some View {
        switch line.kind {
        case .blank:
            Color.clear.frame(height: 6)
        case .rule:
            Hairline().padding(.vertical, 6)
        case .heading1:
            inline.font(.system(size: size + 8, weight: .bold, design: heading)).padding(.top, 2)
        case .heading2:
            inline.font(.system(size: size + 3, weight: .semibold, design: heading)).padding(.top, 4)
        case .heading3:
            inline.font(.system(size: size + 1, weight: .semibold, design: heading)).padding(.top, 4)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(Theme.inkMuted)
                inline
            }
            .font(.system(size: size, design: text))
        case .numbered(let n):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n).").foregroundStyle(Theme.inkMuted).numbers()
                inline
            }
            .font(.system(size: size, design: text))
        case .quote:
            HStack(spacing: 10) {
                Capsule().fill(Theme.inkFaint).frame(width: 3)
                inline.foregroundStyle(Theme.inkSoft)
            }
            .font(.system(size: size, design: text).italic())
            .fixedSize(horizontal: false, vertical: true)
        case .body:
            inline.font(.system(size: size, design: text))
        }
    }

    private var inline: Text {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let a = try? AttributedString(markdown: line.content, options: opts) { return Text(a).foregroundColor(Theme.ink) }
        return Text(line.content).foregroundColor(Theme.ink)
    }
}

private struct BioListPreview: View {
    let list: BioList
    let titles: [Title]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if list.showHeading {
                Text(list.heading).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
            }
            if !list.showsTitles {
                Text("Shows on your profile as set up on the website.").font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
            } else if titles.isEmpty {
                Text("Nothing here yet.").font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
            } else if list.showsCovers {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(titles) { t in
                            Poster(url: t.cover, width: 68, radius: 8, flat: true).accessibilityLabel(t.name)
                        }
                    }
                }
            } else {
                ForEach(Array(titles.enumerated()), id: \.offset) { i, t in
                    Text("\(i + 1). \(t.name)").font(.system(size: 15)).foregroundStyle(Theme.ink)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
