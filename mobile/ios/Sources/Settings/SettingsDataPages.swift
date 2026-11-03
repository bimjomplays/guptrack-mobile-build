import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: 62 import & export

/// Settings › Import & export (62): the last import, the five importers (initials, no logos), export as a file.
struct ImportExportView: View {
    @Environment(AppModel.self) private var model
    @State private var rev = 0

    var body: some View {
        PageLoader(id: "\(rev)", load: { try await $0.importStatus() }) { status in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let last = status.last { LastImportHeader(last: last) }
                    ImporterGroup(sources: status.sources) { rev += 1 }
                    LibraryExportGroup()
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .settingsPage("Import & export")
    }
}

private struct LastImportHeader: View {
    let last: ImportStatus.LastImport

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: last.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(last.ok ? Theme.color(.current) : Theme.danger)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(last.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(last.caption).font(.system(size: 14)).foregroundStyle(Theme.inkMuted).numbers()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.bottom, 24)
        .accessibilityElement(children: .combine)
    }
}

private struct ImporterGroup: View {
    let sources: [ImportStatus.Source]
    var started: () -> Void

    @Environment(AppModel.self) private var model
    @State private var asking: ImportStatus.Source?
    @State private var username = ""

    var body: some View {
        SettingsGroup(label: "Import from", footer: "Imports add to your library. Titles you already have keep your own progress.") {
            ForEach(sources) { s in
                Button { pick(s) } label: {
                    SettingsRow(label: s.name, separator: s.id != sources.last?.id,
                                lead: { SettingsInitials(text: s.initials) },
                                sub: { SettingsSubText(text: s.sub) }, trailing: { EmptyView() })
                }
                .buttonStyle(.plain)
            }
        }
        .alert(asking.map { "Import from \($0.name)" } ?? "", isPresented: Binding(get: { asking != nil },
                                                                                  set: { if !$0 { asking = nil } })) {
            TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Cancel", role: .cancel) { asking = nil }
            Button("Import") { if let s = asking { Task { await start(s) } } }
        } message: {
            Text("Your public list on \(asking?.name ?? "") is read once and added here.")
        }
    }

    private func pick(_ s: ImportStatus.Source) {
        if s.by == "username" {
            username = s.account ?? ""
            asking = s
        } else {
            model.notice = "\(s.name) imports from its export file. Upload the file in Settings › Import & export on the website."
        }
    }

    private func start(_ s: ImportStatus.Source) async {
        let name = username.trimmingCharacters(in: .whitespaces)
        asking = nil
        guard !name.isEmpty else { return }
        if let why = await model.fetch({ try await $0.startImport(s.id, username: name) }).error {
            model.notice = "Couldn't start the import: \(why)"
        } else {
            model.notice = "Importing from \(s.name). Your library updates when it's done."
            started()
        }
    }
}

/// export the library on this iPhone as a JSON or CSV file through the share sheet
private struct LibraryExportGroup: View {
    @Environment(AppModel.self) private var model
    @State private var json: URL?
    @State private var csv: URL?

    var body: some View {
        SettingsGroup(label: "Export", footer: "Every title on your lists with status, progress, score and dates.") {
            share("Export as JSON", json, symbol: "curlybraces")
            share("Export as CSV", csv, symbol: "tablecells", last: true)
        }
        .task { write() }
    }

    @ViewBuilder private func share(_ label: String, _ url: URL?, symbol: String, last: Bool = false) -> some View {
        if let url {
            ShareLink(item: url) { SettingsRow(label, symbol: symbol, chevron: false, separator: !last) }
                .buttonStyle(.plain)
        } else {
            SettingsRow(label, symbol: symbol, chevron: false, separator: !last).opacity(0.4)
        }
    }

    private func write() {
        let dir = FileManager.default.temporaryDirectory
        let j = dir.appendingPathComponent(LibraryExport.fileName("json"))
        let c = dir.appendingPathComponent(LibraryExport.fileName("csv"))
        do {
            try LibraryExport.json(model.library).write(to: j, options: .atomic)
            try Data(LibraryExport.csv(model.library).utf8).write(to: c, options: .atomic)
            json = j
            csv = c
        } catch {
            model.notice = "Couldn't make the export file."
        }
    }
}

// MARK: 63 connected apps

/// Settings › Connected apps (63): pair Harbor with a QR code or the one-time code, the devices with their last sync,
/// disconnect.
struct ConnectedAppsView: View {
    @State private var rev = 0

    var body: some View {
        PageLoader(id: "\(rev)", load: { try await $0.connectedDevices() }) { d in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PairingCode(pairing: d.pairing)
                    DeviceGroup(devices: d.devices) { rev += 1 }
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .settingsPage("Connected apps")
    }
}

private struct PairingCode: View {
    let pairing: ConnectedDevices.Pairing

    var body: some View {
        VStack(spacing: 0) {
            Text("Pair Harbor").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
            Text("In Harbor, open Settings › GupTrack, then scan this code or type it in.")
                .font(.system(size: 15)).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
                .padding(.top, 4)
            SettingsQRCode(text: pairing.qrPayload)
                .frame(width: 168, height: 168)
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.top, 18)
                .accessibilityLabel("QR code for pairing")
            Text(pairing.shownCode)
                .font(.system(size: 30, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.ink)
                .kerning(2)
                .padding(.top, 16)
                .textSelection(.enabled)
                .accessibilityLabel("Code \(pairing.code.map(String.init).joined(separator: " "))")
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(pairing.expiry()).font(.system(size: 14)).foregroundStyle(Theme.inkMuted).numbers()
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.pad)
        .padding(.bottom, 30)
    }
}

/// a QR code drawn with Core Image, sharp at any size
struct SettingsQRCode: View {
    let text: String

    var body: some View {
        if let image = Self.make(text) {
            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
        } else {
            Color.white
        }
    }

    static func make(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage,
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

private struct DeviceGroup: View {
    let devices: [ConnectedDevices.Device]
    var changed: () -> Void

    @Environment(AppModel.self) private var model
    @State private var dropping: ConnectedDevices.Device?

    var body: some View {
        SettingsGroup(label: "Connected", footer: "Disconnecting signs that app out. Pair it again with a new code.") {
            ForEach(devices) { d in row(d) }
        }
        .confirmationDialog(dropping.map { "Disconnect \($0.name)?" } ?? "",
                            isPresented: Binding(get: { dropping != nil }, set: { if !$0 { dropping = nil } }),
                            titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { if let d = dropping { Task { await drop(d) } } }
            Button("Cancel", role: .cancel) { dropping = nil }
        } message: {
            Text("It stops syncing until you pair it again.")
        }
    }

    private func row(_ d: ConnectedDevices.Device) -> some View {
        let mine = d.id == model.account?.deviceId
        return SettingsRow(d.name, symbol: d.symbol, sub: d.caption(thisDevice: mine), chevron: false,
                           separator: d.id != devices.last?.id) {
            if mine {
                SettingsLiveLabel(text: "This iPhone", live: true, size: 14)
            } else {
                Button("Disconnect") { dropping = d }
                    .buttonStyle(.capsule(.tone, .small, color: Theme.danger))
            }
        }
    }

    private func drop(_ d: ConnectedDevices.Device) async {
        dropping = nil
        if let why = await model.fetch({ try await $0.disconnectDevice(d.id) }).error {
            model.notice = "Couldn't disconnect \(d.name): \(why)"
        } else {
            changed()
        }
    }
}

// MARK: 64 backups

/// Settings › Backups (64): the backups with their sizes, Back up now, tap one to restore it (after a confirmation).
struct BackupsView: View {
    @Environment(AppModel.self) private var model
    @State private var rev = 0
    @State private var restoring: BackupList.Backup?
    @State private var working = false

    var body: some View {
        PageLoader(id: "\(rev)", load: { try await $0.backups() }) { list in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    backUp(list)
                    backups(list)
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .settingsPage("Backups")
        .confirmationDialog(restoring.map { "Restore the backup from \($0.when)?" } ?? "",
                            isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
                            titleVisibility: .visible) {
            Button("Restore", role: .destructive) { if let b = restoring { Task { await restore(b) } } }
            Button("Cancel", role: .cancel) { restoring = nil }
        } message: {
            Text("Your library goes back to how it was then. A backup of how it is now is made first.")
        }
    }

    private func backUp(_ list: BackupList) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { Task { await backUpNow() } } label: {
                if working { ProgressView().tint(.white) } else { Label("Back up now", systemImage: "archivebox") }
            }
            .buttonStyle(.capsule(.tint, .large, full: true))
            .disabled(working)
            Text(list.automatic ? list.schedule : "Automatic backups are off.")
                .font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.bottom, 26)
    }

    private func backups(_ list: BackupList) -> some View {
        SettingsGroup(label: "Backups", footer: "Tap a backup to restore it.") {
            ForEach(list.backups) { b in
                Button { restoring = b } label: {
                    SettingsRow(b.when, symbol: "clock.arrow.circlepath", sub: b.note, value: b.size, chevron: false,
                                separator: b.id != list.backups.last?.id)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func backUpNow() async {
        working = true
        defer { working = false }
        if let why = await model.fetch({ try await $0.backUpNow() }).error {
            model.notice = "Couldn't back up: \(why)"
        } else {
            rev += 1
        }
    }

    private func restore(_ b: BackupList.Backup) async {
        restoring = nil
        if let why = await model.fetch({ try await $0.restoreBackup(b.id) }).error {
            model.notice = "Couldn't restore: \(why)"
        } else {
            model.notice = "Restored the backup from \(b.when)."
            await model.syncLibrary()
        }
    }
}

// MARK: 64b accounts

/// Settings › Accounts (64b): the owner's page. Every account on this GupTrack with its role, and who can join.
struct AccountsSettingsView: View {
    var body: some View {
        SettingsLoaded { s in
            if s.account.isOwner {
                PageLoader(load: { try await $0.accountList() }) { list in AccountsList(list: list) }
            } else {
                ContentUnavailableView("Only the owner can manage accounts", systemImage: "person.2.slash",
                                       description: Text("Ask the owner of this GupTrack to invite or remove people."))
            }
        }
        .settingsPage("Accounts")
    }
}

private struct AccountsList: View {
    let list: AccountList

    @Environment(AppModel.self) private var model
    @State private var joining: String
    @State private var invite: AccountList.Invite?

    init(list: AccountList) {
        self.list = list
        _joining = State(initialValue: list.joining)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsGroup(label: "\(list.accounts.count) accounts") {
                    ForEach(list.sorted) { m in member(m) }
                }
                joiningGroup
            }
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .onChange(of: joining) { _, v in Task { await setJoining(v) } }
    }

    private func member(_ m: AccountList.Member) -> some View {
        SettingsRow(label: m.user.name, value: m.roleLabel, chevron: false, separator: m.id != list.sorted.last?.id,
                    lead: { Avatar(url: m.user.avatar, size: 36) },
                    sub: { SettingsSubText(text: "@\(m.user.username) · \(m.caption)") }, trailing: { EmptyView() })
    }

    private var joiningGroup: some View {
        SettingsGroup(label: "Joining", footer: footer) {
            SettingsPickerRow(label: "Who can make an account", choices: AccountList.joiningChoices, selection: $joining)
            if let invite {
                ShareLink(item: invite.url) {
                    SettingsRow("Share invite link", symbol: "square.and.arrow.up", sub: invite.url.absoluteString,
                                chevron: false, separator: false, tint: true)
                }
                .buttonStyle(.plain)
            } else {
                Button { Task { await makeInvite() } } label: {
                    SettingsRow("Create invite link", symbol: "link.badge.plus", chevron: false, separator: false, tint: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: String {
        if let invite { return "The link works once and expires \(Format.longDay(invite.expiresAt))." }
        return "Invite links work once. People who join can only see what others share."
    }

    private func makeInvite() async {
        switch await model.fetch({ try await $0.createInvite() }) {
        case .loaded(let i): invite = i
        case .failed(let why): model.notice = "Couldn't make an invite link: \(why)"
        case .loading: break
        }
    }

    private func setJoining(_ v: String) async {
        if let why = await model.fetch({ try await $0.setJoining(v) }).error {
            model.notice = "Couldn't change who can join: \(why)"
        }
    }
}
