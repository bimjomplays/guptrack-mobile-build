import SwiftUI

// The settings pages' own rows (design/iphone/screens/_settings.mjs): plain hairline rows on the page, a plain
// SF Symbol in ink-soft (not the Kit PlainRow's filled square), pull-down values with the up-down chevron,
// switches and checkmarks. And the shared loader for the account's settings (AccountSettingsStore).

/// one settings row: icon or a lead view, the label with a sub line, a value, something on the right, a chevron
struct SettingsRow<Lead: View, Sub: View, Trailing: View>: View {
    let label: String
    var symbol: String?
    var value: String?
    var chevron = true
    /// a pull-down's ⌃⌄ instead of the chevron
    var menu = false
    var separator = true
    var danger = false
    var tint = false
    var minHeight: CGFloat = 52
    @ViewBuilder var lead: () -> Lead
    @ViewBuilder var sub: () -> Sub
    @ViewBuilder var trailing: () -> Trailing

    private var labelColor: Color { danger ? Theme.danger : tint ? Theme.brandSoft : Theme.ink }

    var body: some View {
        HStack(spacing: 14) {
            lead()
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(danger ? Theme.danger : tint ? Theme.brandSoft : Theme.inkSoft)
                    .frame(width: 26)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 17)).foregroundStyle(labelColor)
                    sub()
                }
                .padding(.vertical, 12)
                Spacer(minLength: 8)
                if let value {
                    Text(value).font(.system(size: 17)).foregroundStyle(Theme.inkMuted).lineLimit(1).numbers()
                }
                trailing()
                if menu {
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.inkMuted)
                } else if chevron {
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            .padding(.trailing, Theme.pad)
            .frame(minHeight: minHeight)
            .overlay(alignment: .bottom) { if separator { Hairline() } }
        }
        .padding(.leading, Theme.pad)
        .contentShape(Rectangle())
    }
}

extension SettingsRow where Lead == EmptyView, Sub == SettingsSubText, Trailing == EmptyView {
    init(_ label: String, symbol: String? = nil, sub: String? = nil, value: String? = nil, chevron: Bool = true,
         menu: Bool = false, separator: Bool = true, danger: Bool = false, tint: Bool = false) {
        self.init(label: label, symbol: symbol, value: value, chevron: chevron, menu: menu, separator: separator,
                  danger: danger, tint: tint, lead: { EmptyView() }, sub: { SettingsSubText(text: sub) },
                  trailing: { EmptyView() })
    }
}

extension SettingsRow where Lead == EmptyView, Sub == SettingsSubText {
    init(_ label: String, symbol: String? = nil, sub: String? = nil, value: String? = nil, chevron: Bool = true,
         separator: Bool = true, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(label: label, symbol: symbol, value: value, chevron: chevron, separator: separator,
                  lead: { EmptyView() }, sub: { SettingsSubText(text: sub) }, trailing: trailing)
    }
}

/// the 13pt grey line under a row's label
struct SettingsSubText: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// a green (or grey) dot and a short state: "● Connected"
struct SettingsLiveLabel: View {
    let text: String
    var live = true
    var size: CGFloat = 15

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(live ? Theme.color(.current) : Theme.inkFaint).frame(width: 7, height: 7)
            Text(text).font(.system(size: size)).foregroundStyle(Theme.inkMuted)
        }
    }
}

/// a switch row
struct SettingsToggleRow: View {
    let label: String
    var sub: String?
    var symbol: String?
    var separator = true
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(label, symbol: symbol, sub: sub, chevron: false, separator: separator) {
            Toggle(label, isOn: $isOn).labelsHidden().tint(Theme.color(.current))
        }
        .accessibilityElement(children: .combine)
    }
}

/// a single-choice row with the brand checkmark
struct SettingsCheckRow: View {
    let label: String
    let checked: Bool
    var separator = true
    var pick: () -> Void

    var body: some View {
        Button(action: pick) {
            SettingsRow(label, chevron: false, separator: separator) {
                if checked {
                    Image(systemName: "checkmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.brandSoft)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

/// A pull-down row: the value with ⌃⌄, a menu of the choices with a checkmark on the current one.
struct SettingsPickerRow<T: Hashable>: View {
    let label: String
    let choices: [(T, String)]
    var separator = true
    @Binding var selection: T

    var body: some View {
        Menu {
            Picker(label, selection: $selection) {
                ForEach(choices, id: \.0) { c in Text(c.1).tag(c.0) }
            }
        } label: {
            SettingsRow(label, value: choices.first { $0.0 == selection }?.1, menu: true, separator: separator)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(choices.first { $0.0 == selection }?.1 ?? "")")
    }
}

/// rows under a small label with a hairline above and below, an optional footer
struct SettingsGroup<Content: View>: View {
    var label: String?
    var footer: String?
    var gap: CGFloat = 26
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label {
                Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, Theme.pad).padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
            }
            Hairline()
            content()
            Hairline()
            if let footer {
                Text(footer).font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.pad).padding(.top, 8)
            }
        }
        .padding(.bottom, gap)
    }
}

/// initials in a hairline ring, standing in for a service's logo
struct SettingsInitials: View {
    let text: String
    var size: CGFloat = 30

    var body: some View {
        Text(text)
            .font(.system(size: text.count > 2 ? 10 : 11.5, weight: .bold))
            .foregroundStyle(Theme.inkSoft)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

// MARK: the account's settings, shared

/// Loads the account's settings once into AccountSettingsStore.shared, then shows the page with them.
struct SettingsLoaded<Content: View>: View {
    @ViewBuilder let content: (AccountSettings) -> Content

    @Environment(AppModel.self) private var model
    @State private var error: String?

    private var store: AccountSettingsStore { AccountSettingsStore.shared }

    var body: some View {
        Group {
            if let s = store.settings, !store.needsLoad(for: model.account?.user.username) {
                content(s)
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't load your settings", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try again") { Task { await load() } }.buttonStyle(.capsule(.tone, .small))
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { if store.needsLoad(for: model.account?.user.username) { await load() } }
    }

    private func load() async {
        error = nil
        switch await model.fetch({ try await $0.accountSettings() }) {
        case .loaded(let s): store.loaded(s, for: model.account?.user.username)
        case .failed(let why): error = why
        case .loading: break
        }
    }
}

extension AppModel {
    /// change the account's settings now and send the change a moment later (one PATCH for a burst of edits)
    func editSettings(delay: Double = 0.5, _ change: (inout AccountSettings) -> Void) {
        let store = AccountSettingsStore.shared
        store.edit(change, send: { [weak self] in
            guard let self else { return }
            if let why = await self.fetch({ try await store.save(using: $0) }).error {
                self.notice = "Couldn't save that setting: \(why)"
            }
        }, delay: delay)
    }

    /// a binding into the shared settings that saves what's set
    func settingsBinding<V>(_ path: WritableKeyPath<AccountSettings, V>, fallback: V, delay: Double = 0.5) -> Binding<V> {
        Binding(
            get: { AccountSettingsStore.shared.settings?[keyPath: path] ?? fallback },
            set: { v in self.editSettings(delay: delay) { $0[keyPath: path] = v } }
        )
    }
}

extension View {
    /// a settings page's frame: inline title, the page background
    func settingsPage(_ title: String) -> some View {
        self
            .pageBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
