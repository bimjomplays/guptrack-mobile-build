import PhotosUI
import SwiftUI

// MARK: 56 profile

/// Settings › Profile (56): a live banner preview, then name, picture, banner and bio (the bio opens the bio editor),
/// and the banner fade as native controls. The fade is the approved exception to "no gradients".
struct ProfileSettingsView: View {
    var body: some View {
        SettingsLoaded { s in ProfileSettingsForm(settings: s) }
            .settingsPage("Profile")
    }
}

private struct ProfileSettingsForm: View {
    let settings: AccountSettings
    @Environment(AppModel.self) private var model
    @State private var renaming = false
    @State private var newName = ""
    @State private var photo: PhotosPickerItem?
    @State private var picked: UIImage?

    private var p: AccountSettings.Profile { settings.profile }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ProfileBannerPreview(profile: p, joined: settings.account.joined, picked: picked) {
                    bannerMenu { bannerChangeLabel }
                }
                .padding(.horizontal, Theme.pad)
                .padding(.bottom, 24)
                rows
                fade
            }
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .alert("Display name", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { model.editSettings(delay: 0) { $0.profile.displayName = name } }
            }
        } message: {
            Text("How your name shows on your profile, in activity and in messages.")
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    private var rows: some View {
        SettingsGroup {
            Button {
                newName = p.displayName
                renaming = true
            } label: { SettingsRow("Name", value: p.displayName) }
            .buttonStyle(.plain)
            PhotosPicker(selection: $photo, matching: .images) {
                SettingsRow("Picture") { pictureThumb }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Picture")
            bannerMenu { SettingsRow("Banner", value: p.bannerName ?? "None") }
            Button { model.sheet = .bioEditor } label: {
                SettingsRow("Bio", value: BioDocument.summary(p.bio), separator: false)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var pictureThumb: some View {
        if let picked {
            Image(uiImage: picked).resizable().scaledToFill().frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            Avatar(url: p.avatar, size: 30)
        }
    }

    private var bannerChangeLabel: some View {
        Label("Change", systemImage: "photo")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color.black.opacity(0.35), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
    }

    /// banners come from the art of titles on your list
    private func bannerMenu<L: View>(@ViewBuilder label: () -> L) -> some View {
        let choices = bannerChoices
        return Menu {
            Section("From your library") {
                ForEach(choices, id: \.id) { e in
                    Button(e.title.name) {
                        model.editSettings(delay: 0) {
                            $0.profile.banner = e.title.banner
                            $0.profile.bannerName = e.title.name
                        }
                    }
                }
            }
            if p.banner != nil {
                Button("No banner", role: .destructive) {
                    model.editSettings(delay: 0) {
                        $0.profile.banner = nil
                        $0.profile.bannerName = nil
                    }
                }
            }
        } label: { label() }
        .buttonStyle(.plain)
    }

    private var bannerChoices: [LibraryEntry] {
        let withArt = model.library.filter { $0.title.banner != nil }
        let favs = withArt.filter(\.favourite)
        let rest = withArt.filter { !$0.favourite }.sorted { $0.updatedAt > $1.updatedAt }
        return Array((favs + rest).prefix(12))
    }

    private var fade: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Banner fade").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, Theme.pad).padding(.bottom, 6)
            Hairline()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Strength")
                    Spacer()
                    Text("\(p.fade)%").foregroundStyle(Theme.inkMuted).numbers()
                }
                .font(.system(size: 17)).foregroundStyle(Theme.ink)
                Slider(value: Binding(get: { Double(p.fade) }, set: { v in model.editSettings { $0.profile.fade = Int(v) } }),
                       in: 0...100, step: 5)
                    .tint(Theme.brand)
                    .accessibilityLabel("Fade strength")
                    .padding(.top, 4)
                Text("Fade colour").font(.system(size: 17)).foregroundStyle(Theme.ink).padding(.top, 14).padding(.bottom, 10)
                Picker("Fade colour", selection: model.settingsBinding(\.profile.fadeColour, fallback: .dark, delay: 0)) {
                    ForEach(AccountSettings.FadeColour.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Banner text").font(.system(size: 17)).foregroundStyle(Theme.ink).padding(.top, 16).padding(.bottom, 10)
                Picker("Banner text", selection: model.settingsBinding(\.profile.bannerText, fallback: .auto, delay: 0)) {
                    ForEach(AccountSettings.BannerText.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, 12)
            .padding(.bottom, 18)
            Hairline()
        }
        .padding(.bottom, 26)
    }

    private func upload(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else {
            model.notice = "Couldn't read that picture."
            return
        }
        let small = Self.square(img, side: 512)
        picked = small
        guard let jpeg = small.jpegData(compressionQuality: 0.85) else { return }
        if let why = await model.fetch({ try await $0.uploadPicture(jpeg) }).error {
            model.notice = "Couldn't change your picture: \(why)"
        }
    }

    /// the middle square of a picture, `side` points across
    static func square(_ img: UIImage, side: CGFloat) -> UIImage {
        let s = min(img.size.width, img.size.height)
        let scale = side / max(1, s)
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            img.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }
    }
}

/// The profile banner as the profile shows it: the art, the fade, the picture and name in the corner.
struct ProfileBannerPreview<Action: View>: View {
    let profile: AccountSettings.Profile
    let joined: Date
    var picked: UIImage?
    @ViewBuilder var action: () -> Action

    private var fadeColour: Color { profile.fadeColour == .dark ? .black : Theme.sheet }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        Artwork(url: profile.banner)
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .overlay {
                // the approved banner fade (the website's profile banner)
                LinearGradient(stops: [.init(color: fadeColour.opacity(0), location: 0.2),
                                       .init(color: fadeColour.opacity(Double(profile.fade) / 100), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) { identity.padding(.leading, 14).padding(.bottom, 12) }
            .overlay(alignment: .topTrailing) { action().padding(10) }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.keyline, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 6)
    }

    private var identity: some View {
        HStack(spacing: 10) {
            if let picked {
                Image(uiImage: picked).resizable().scaledToFill().frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            } else {
                Avatar(url: profile.avatar, size: 44)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                Text("Joined \(Format.longDay(joined))").font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
            }
            .modifier(BannerTextStyle(style: profile.bannerText))
        }
    }
}

/// the banner text's legibility: a shadow, a dark backing, or nothing
private struct BannerTextStyle: ViewModifier {
    let style: AccountSettings.BannerText

    func body(content: Content) -> some View {
        switch style {
        case .auto, .shadow:
            content.shadow(color: .black.opacity(0.6), radius: 3, y: 1)
        case .backing:
            content.padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .none:
            content
        }
    }
}

// MARK: 58 privacy

/// Settings › Privacy (58): who sees the profile as checkmarks; each list, comments and messages as pull-downs.
struct PrivacySettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsLoaded { s in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    profileGroup(s)
                    lists(s)
                    reach
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .settingsPage("Privacy")
    }

    private func profileGroup(_ s: AccountSettings) -> some View {
        SettingsGroup(label: "Who can see your profile",
                      footer: "Public means everyone signed in to your GupTrack. Private shows it only to you.") {
            ForEach(Visibility.allCases) { v in
                SettingsCheckRow(label: v.label, checked: s.privacy.profile == v, separator: v != .private) {
                    model.editSettings(delay: 0) { $0.privacy.profile = v }
                }
            }
        }
    }

    private func lists(_ s: AccountSettings) -> some View {
        SettingsGroup(label: "Lists") {
            ForEach(MediaKind.allCases) { m in
                SettingsPickerRow(label: m.plural, choices: Visibility.allCases.map { ($0, $0.label) },
                                  separator: m != MediaKind.allCases.last,
                                  selection: Binding(get: { s.privacy.list(m) },
                                                     set: { v in model.editSettings(delay: 0) { $0.privacy.lists[m.rawValue] = v } }))
            }
        }
    }

    private var reach: some View {
        let choices = AccountSettings.Reach.allCases.map { ($0, $0.label) }
        return SettingsGroup(label: "Who can reach you") {
            SettingsPickerRow(label: "Comments on your profile", choices: choices,
                              selection: model.settingsBinding(\.privacy.comments, fallback: .friends, delay: 0))
            SettingsPickerRow(label: "Messages", choices: choices, separator: false,
                              selection: model.settingsBinding(\.privacy.messages, fallback: .everyone, delay: 0))
        }
    }
}

// MARK: 59 appearance

/// Settings › Appearance (59): the website's 18 themes as small flat Home previews in four shelves.
struct AppearanceSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsLoaded { s in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(SettingsThemes.shelves) { shelf in
                        ThemeShelf(shelf: shelf, picked: s.theme) { name in
                            model.editSettings(delay: 0) { $0.theme = name }
                        }
                    }
                    Text("Your theme follows your account, so the website and this iPhone match.")
                        .font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                        .padding(.horizontal, Theme.pad).padding(.top, -6)
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .settingsPage("Appearance")
    }
}

private struct ThemeShelf: View {
    let shelf: SettingsThemes.Shelf
    let picked: String
    var pick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(shelf.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, Theme.pad).padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(shelf.themes) { t in
                        Button { pick(t.name) } label: { ThemeTile(look: t, selected: t.name == picked) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(t.name)
                            .accessibilityAddTraits(t.name == picked ? .isSelected : [])
                    }
                }
                .padding(.horizontal, Theme.pad)
                .padding(.vertical, 6)
            }
        }
        .padding(.bottom, 14)
    }
}

private struct ThemeTile: View {
    let look: SettingsThemes.Look
    let selected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 8) {
            preview
                .frame(width: 68, height: 92)
                .clipShape(shape)
                .overlay {
                    if selected {
                        shape.inset(by: -4).strokeBorder(Theme.brand, lineWidth: 2)
                    } else {
                        shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    }
                }
                .overlay(alignment: .bottomTrailing) { if selected { check } }
            Text(look.name)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.ink : Theme.inkMuted)
                .lineLimit(1)
                .frame(width: 76)
        }
    }

    @ViewBuilder private var preview: some View {
        if look.split, let light = SettingsThemes.named("Light") {
            ZStack {
                MiniHome(look: look)
                MiniHome(look: light).clipShape(LowerTriangle())
            }
        } else {
            MiniHome(look: look)
        }
    }

    private var check: some View {
        Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Theme.brand, in: Circle())
            .overlay(Circle().strokeBorder(Theme.sheet, lineWidth: 2))
            .padding(.trailing, 5).padding(.bottom, 14)
    }
}

/// a theme's Home page in miniature, flat colours only: banner, a row of covers, two text lines, the tab bar
private struct MiniHome: View {
    let look: SettingsThemes.Look

    private var page: Color { Color(hex: look.page) }
    private var card: Color { Color(hex: look.card) }
    private var accent: Color { Color(hex: look.accent) }
    private var ink: Color { Color(hex: look.ink) }

    var body: some View {
        ZStack(alignment: .bottom) {
            page
            VStack(alignment: .leading, spacing: 0) {
                banner.frame(height: 20).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                HStack(spacing: 4) {
                    accentBlock.clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    card.clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    card.clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                .frame(height: 22)
                .padding(.top, 7)
                GeometryReader { g in
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(ink.opacity(0.75)).frame(width: g.size.width * 0.7, height: 4)
                        Capsule().fill(ink.opacity(0.35)).frame(width: g.size.width * 0.46, height: 4)
                    }
                }
                .frame(height: 12)
                .padding(.top, 8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.top, 8)
            HStack {
                ForEach(0..<4, id: \.self) { i in
                    Circle().fill(i == 0 ? accent : ink.opacity(0.35)).frame(width: 4, height: 4)
                    if i < 3 { Spacer(minLength: 0) }
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 9)
            .background(card, in: Capsule())
            .padding(.horizontal, 7)
            .padding(.bottom, 7)
        }
    }

    /// the banner: the accent over the card (flat), or the two accents side by side
    @ViewBuilder private var banner: some View {
        if let a2 = look.accent2 {
            HStack(spacing: 0) { accent; Color(hex: a2) }
        } else {
            ZStack { card; accent.opacity(0.33) }
        }
    }

    @ViewBuilder private var accentBlock: some View {
        if let a2 = look.accent2 {
            VStack(spacing: 0) { accent; Color(hex: a2) }
        } else {
            accent
        }
    }
}

/// the lower-right half of a rectangle (Match system's light half)
private struct LowerTriangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
