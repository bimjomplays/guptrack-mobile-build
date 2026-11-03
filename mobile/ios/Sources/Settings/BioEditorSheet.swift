import SwiftUI

/// The bio editor (57): a full-height sheet. Write (the markdown, with lists from the library as blocks) and Preview,
/// swiped between on iPhone; the profile's bio presets; a formatting bar with Insert list.
struct BioEditorSheet: View {
    @Environment(AppModel.self) private var model
    @State private var doc = BioDocument(AccountSettingsStore.shared.settings?.profile.bio ?? "")
    @State private var preset = AccountSettingsStore.shared.settings?.profile.bioPreset ?? .editorial
    @State private var mode = 0
    @State private var lists: [CustomList] = []
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
                    BioPreview(doc: doc, preset: preset, lists: lists).tag(1)
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
        .task {
            await loadSettings()
            await loadLists()
        }
    }

    /// opened straight from a link: the settings may not be here yet
    private func loadSettings() async {
        let store = AccountSettingsStore.shared
        guard store.needsLoad(for: model.account?.user.username) else { return }
        guard case .loaded(let s) = await model.fetch({ try await $0.accountSettings() }) else { return }
        store.loaded(s, for: model.account?.user.username)
        doc = BioDocument(s.profile.bio)
        preset = s.profile.bioPreset
    }

    private var presets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Presets").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .padding(.trailing, 2)
                ForEach(AccountSettings.BioPreset.allCases) { p in
                    Button(p.label) { preset = p }
                        .buttonStyle(.capsule(p == preset ? .tint : .tone, .small))
                        .accessibilityAddTraits(p == preset ? .isSelected : [])
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
                    case .list(let ref): listBlock(i, ref)
                    }
                }
                Text("Markdown works here. Split view is on iPad and the website; on iPhone, swipe between Write and Preview.")
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

    private func listBlock(_ i: Int, _ ref: BioDocument.ListRef) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "list.bullet.rectangle").font(.system(size: 17)).foregroundStyle(Theme.brandSoft)
            VStack(alignment: .leading, spacing: 1) {
                Text(BioListInfo.name(ref, lists: lists)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(SettingsText.titles(BioListInfo.titles(ref, lists: lists, library: model.library).count)
                     + " · " + ref.styleLabel)
                    .font(.system(size: 12.5)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 0)
            Menu {
                Button("Show as cover row", systemImage: "rectangle.grid.1x2") { restyle(i, "covers") }
                Button("Show as list", systemImage: "list.bullet") { restyle(i, "list") }
                Button("Remove", systemImage: "trash", role: .destructive) { doc.remove(at: i) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("List options")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.brand.opacity(0.35), lineWidth: 0.5))
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, 6)
    }

    private func restyle(_ i: Int, _ style: String) {
        guard doc.blocks.indices.contains(i), case .list(var ref) = doc.blocks[i] else { return }
        ref.style = style
        doc.blocks[i] = .list(ref)
    }

    // MARK: the formatting bar

    @ViewBuilder private var formatBar: some View {
        ForEach(BioDocument.Style.allCases, id: \.self) { style in
            Button { format(style) } label: { Image(systemName: style.symbol) }
                .accessibilityLabel(style.label)
        }
        Spacer()
        insertMenu
    }

    private var insertMenu: some View {
        Menu {
            Section("Favourites") {
                ForEach(MediaKind.allCases) { m in
                    if model.library.contains(where: { $0.favourite && $0.media == m }) {
                        Button("Favourites · \(m.plural)") { insert("favourites:\(m.rawValue)") }
                    }
                }
            }
            if !lists.isEmpty {
                Section("Your lists") {
                    ForEach(lists) { l in Button(l.name) { insert(l.id) } }
                }
            }
        } label: {
            Label("Insert list", systemImage: "text.badge.plus")
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.brand)
    }

    /// the text block being edited, else the last one
    private var target: Int? {
        if let focused, doc.blocks.indices.contains(focused), case .text = doc.blocks[focused] { return focused }
        return doc.blocks.indices.last { if case .text = doc.blocks[$0] { return true } else { return false } }
    }

    private func format(_ style: BioDocument.Style) {
        guard let i = target, case .text(let s) = doc.blocks[i] else { return }
        doc.blocks[i] = .text(style.apply(s))
        focused = i
    }

    private func insert(_ id: String) {
        doc.insert(BioDocument.ListRef(id: id, style: "covers"), after: target)
    }

    private func loadLists() async {
        if case .loaded(let l) = await model.fetch({ try await $0.customLists() }) { lists = l }
    }

    private func save() {
        let text = doc.text
        let p = preset
        model.editSettings(delay: 0) {
            $0.profile.bio = text
            $0.profile.bioPreset = p
        }
        model.sheet = nil
    }
}

/// a bio list block's name and titles, from the library (favourites) or the custom lists
enum BioListInfo {
    static func name(_ ref: BioDocument.ListRef, lists: [CustomList]) -> String {
        if let m = ref.favouritesMedia { return "Favourites · \(m.plural)" }
        return lists.first { $0.id == ref.id }?.name ?? "A list"
    }

    static func titles(_ ref: BioDocument.ListRef, lists: [CustomList], library: [LibraryEntry]) -> [Title] {
        if let m = ref.favouritesMedia { return library.filter { $0.favourite && $0.media == m }.map(\.title) }
        return lists.first { $0.id == ref.id }?.items.map(\.title) ?? []
    }
}

/// the bio as the profile shows it, in the picked preset's type
private struct BioPreview: View {
    let doc: BioDocument
    let preset: AccountSettings.BioPreset
    let lists: [CustomList]

    @Environment(AppModel.self) private var model

    private var design: Font.Design {
        switch preset {
        case .ledger: return .monospaced
        case .editorial: return .serif
        case .shelf, .minimal: return .default
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(doc.blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let s):
                        ForEach(Array(BioDocument.lines(s).enumerated()), id: \.offset) { _, line in BioLineView(line: line, design: design, minimal: preset == .minimal) }
                    case .list(let ref):
                        BioListPreview(ref: ref, titles: BioListInfo.titles(ref, lists: lists, library: model.library),
                                       big: preset == .shelf)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.pad)
            .padding(.vertical, 16)
        }
    }
}

private struct BioLineView: View {
    let line: BioDocument.Line
    let design: Font.Design
    let minimal: Bool

    var body: some View {
        switch line.kind {
        case .blank:
            Color.clear.frame(height: 6)
        case .heading1:
            inline.font(.system(size: minimal ? 18 : 24, weight: .bold, design: design)).padding(.top, 2)
        case .heading2:
            inline.font(.system(size: minimal ? 16 : 19, weight: .semibold, design: design)).padding(.top, 4)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(Theme.inkMuted)
                inline
            }
            .font(.system(size: 16, design: design))
        case .quote:
            HStack(spacing: 10) {
                Capsule().fill(Theme.inkFaint).frame(width: 3)
                inline.foregroundStyle(Theme.inkSoft)
            }
            .font(.system(size: 16, design: design).italic())
            .fixedSize(horizontal: false, vertical: true)
        case .body:
            inline.font(.system(size: 16, design: design))
        }
    }

    private var inline: Text {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let a = try? AttributedString(markdown: line.content, options: opts) { return Text(a) }
        return Text(line.content)
    }
}

private struct BioListPreview: View {
    let ref: BioDocument.ListRef
    let titles: [Title]
    let big: Bool

    var body: some View {
        if ref.style == "list" {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(titles.prefix(10).enumerated()), id: \.offset) { i, t in
                    Text("\(i + 1). \(t.name)").font(.system(size: 15)).foregroundStyle(Theme.ink)
                }
            }
            .padding(.vertical, 4)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(titles.prefix(10))) { t in
                        Poster(url: t.cover, width: big ? 92 : 68, radius: 8, flat: true)
                            .accessibilityLabel(t.name)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}
