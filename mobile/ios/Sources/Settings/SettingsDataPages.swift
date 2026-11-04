import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers

// MARK: 62 import & export

/// Settings › Import & export (62): the five importers (initials, no logos), the running import with its preview,
/// then export as files.
struct ImportExportView: View {
    @Environment(AppModel.self) private var model
    @State private var job: ImportJob?
    @State private var polls = 0
    @State private var askingName = false
    @State private var username = ""
    @State private var fileSource: ImportSource = .mal
    @State private var pickingFiles = false
    @State private var exportFile: DataFile?
    @State private var exporting = false
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let job {
                    ImportJobSection(job: job, working: working, skip: { m in Task { await skip(m) } },
                                     commit: { Task { await commit() } }, close: { self.job = nil })
                } else {
                    importers
                }
                exports
            }
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .settingsPage("Import & export")
        .alert("Import from AniList", isPresented: $askingName) {
            TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Import") { Task { await startAniList() } }
        } message: {
            Text("Your public AniList lists are read once and checked here before anything is added.")
        }
        .fileImporter(isPresented: $pickingFiles, allowedContentTypes: Self.types(fileSource),
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await startFiles(urls) } }
        }
        .fileExporter(isPresented: $exporting, document: exportFile, contentType: .data,
                      defaultFilename: exportFile?.name) { _ in }
        .task(id: polls) { await poll() }
    }

    private var importers: some View {
        SettingsGroup(label: "Import from", footer: "You see what an import adds and changes before anything is saved.") {
            ForEach(ImportSource.allCases) { s in
                Button { pick(s) } label: {
                    SettingsRow(label: s.label, separator: s != ImportSource.allCases.last,
                                lead: { SettingsInitials(text: Self.initials(s)) },
                                sub: { SettingsSubText(text: s.fileHint) }, trailing: { EmptyView() })
                }
                .buttonStyle(.plain)
                .disabled(working)
            }
        }
    }

    private var exports: some View {
        SettingsGroup(label: "Export", footer: "The backup file has everything: lists, reviews, custom lists and settings. Restore it in Backups.") {
            ForEach(ExportKind.allCases) { k in
                Button { Task { await export(k) } } label: { SettingsRow(k.label, symbol: k.symbol, chevron: false) }
                    .buttonStyle(.plain)
            }
            Button { Task { await exportBackup() } } label: {
                SettingsRow("Full backup", symbol: "archivebox", sub: "guptrack-backup.json", chevron: false, separator: false)
            }
            .buttonStyle(.plain)
        }
        .disabled(working)
    }

    static func initials(_ s: ImportSource) -> String {
        switch s {
        case .anilist: return "AL"
        case .mal: return "MAL"
        case .letterboxd: return "LB"
        case .trakt: return "TR"
        case .goodreads: return "GR"
        }
    }

    static func types(_ s: ImportSource) -> [UTType] {
        switch s {
        case .mal: return [.xml]
        case .trakt: return [.json]
        case .letterboxd, .goodreads: return [.commaSeparatedText, .plainText]
        case .anilist: return []
        }
    }

    private func pick(_ s: ImportSource) {
        if s == .anilist {
            askingName = true
        } else {
            fileSource = s
            pickingFiles = true
        }
    }

    private func started(_ answer: Load<ImportJob>) {
        switch answer {
        case .loaded(let j):
            job = j
            polls += 1
        case .failed(let why): model.notice = "Couldn't start the import: \(why)"
        case .loading: break
        }
    }

    private func startAniList() async {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        working = true
        defer { working = false }
        started(await model.fetch { try await $0.importAniList(name) })
    }

    private func startFiles(_ urls: [URL]) async {
        var files: [FileImportBody.File] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            files.append(FileImportBody.file(name: url.lastPathComponent, data: data))
        }
        guard !files.isEmpty else {
            model.notice = "Couldn't read those files."
            return
        }
        working = true
        defer { working = false }
        let source = fileSource
        if source == .mal {
            let xml = files.filter { $0.base64 != true }.map(\.data)
            started(await model.fetch { try await $0.importMAL(xml) })
        } else {
            started(await model.fetch { try await $0.importFiles(source, files) })
        }
    }

    /// ask how a running import is doing, once a second
    private func poll() async {
        guard let j = job, j.running else { return }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard !Task.isCancelled else { return }
        if case .loaded(let next) = await model.fetch({ try await $0.importJob(j.id) }) {
            job = next
            if next == nil { model.notice = "That import has ended." }
        }
        polls += 1
    }

    private func skip(_ m: ImportJob.Miss) async {
        guard let j = job else { return }
        switch await model.fetch({ try await $0.skipImported(j.id, key: m.key) }) {
        case .loaded(let next): job = next
        case .failed(let why): model.notice = "Couldn't leave \(m.title) out: \(why)"
        case .loading: break
        }
    }

    private func commit() async {
        guard let j = job else { return }
        working = true
        defer { working = false }
        switch await model.fetch({ try await $0.commitImport(j.id) }) {
        case .loaded(let next):
            job = next
            polls += 1
            if next?.phase == "done" { await model.syncLibrary() }
        case .failed(let why): model.notice = "Couldn't import: \(why)"
        case .loading: break
        }
    }

    private func export(_ k: ExportKind) async {
        working = true
        defer { working = false }
        switch await model.fetch({ try await $0.exportFile(k) }) {
        case .loaded(let f):
            exportFile = DataFile(name: f.name, data: Data(f.text.utf8))
            exporting = true
        case .failed(let why): model.notice = "Couldn't export: \(why)"
        case .loading: break
        }
    }

    private func exportBackup() async {
        working = true
        defer { working = false }
        switch await model.fetch({ try await $0.exportBackup() }) {
        case .loaded(let json):
            guard let data = try? APIClient.encoder.encode(json) else { return }
            exportFile = DataFile(name: "guptrack-backup.json", data: data)
            exporting = true
        case .failed(let why): model.notice = "Couldn't make the backup: \(why)"
        case .loading: break
        }
    }
}

/// an import: where it's up to, what it would do per list, the titles it couldn't find, then Import
private struct ImportJobSection: View {
    let job: ImportJob
    let working: Bool
    var skip: (ImportJob.Miss) -> Void
    var commit: () -> Void
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if job.phase == "ready" || job.phase == "done" { plan }
            if job.phase == "ready" && !job.openMisses.isEmpty { misses }
            actions
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(job.sourceName) · \(job.name)").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(job.phase == "done" ? job.resultLine ?? job.phaseLine : job.phaseLine)
                .font(.system(size: 14)).foregroundStyle(job.phase == "failed" ? Theme.danger : Theme.inkMuted).numbers()
            if job.running {
                ProgressView(value: job.progress).tint(Theme.brand).padding(.top, 6)
            }
            ForEach(job.notes ?? [], id: \.self) { n in
                Text(n).font(.system(size: 13)).foregroundStyle(Theme.inkMuted).padding(.top, 4)
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.bottom, 20)
        .accessibilityElement(children: .combine)
    }

    private var plan: some View {
        SettingsGroup(label: job.phase == "done" ? "Imported" : "What this import does") {
            ForEach(job.plan, id: \.media) { p in
                SettingsRow(p.media.kind.plural,
                            sub: ImportJob.countsLine(added: p.decisions.added, updated: p.decisions.updated,
                                                      unchanged: p.decisions.unchanged, kept: p.decisions.kept),
                            value: SettingsText.titles(p.entries), chevron: false,
                            separator: p.media != job.plan.last?.media)
            }
        }
    }

    private var misses: some View {
        let open = job.openMisses
        return SettingsGroup(label: "Not found", footer: "Titles left here aren't imported. Matching them to a title by hand is on the website.") {
            ForEach(open) { m in
                SettingsRow(m.title, sub: [m.media.kind.plural, m.year.map(String.init), m.reason].compactMap { $0 }
                                .joined(separator: " · "),
                            chevron: false, separator: m.id != open.last?.id) {
                    Button("Leave out") { skip(m) }.buttonStyle(.capsule(.tone, .small))
                }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 10) {
            if job.phase == "ready" {
                Button(action: commit) {
                    if working { ProgressView().tint(.white) } else { Text("Import") }
                }
                .buttonStyle(.capsule(.tint, .large, full: true))
                .disabled(working)
            }
            if !job.running {
                Button(job.phase == "ready" ? "Cancel" : "Done", action: close)
                    .buttonStyle(.capsule(.tone, .large, full: true))
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.bottom, 26)
    }
}

/// a file to save to Files
struct DataFile: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

    var name: String
    var data: Data

    init(name: String, data: Data) {
        self.name = name
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        name = configuration.file.filename ?? "file"
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: 63 connected apps

/// Settings › Connected apps (63): connect Harbor or another iPhone with a one-time code (and its QR), the devices
/// signed in with their last use, disconnect.
struct ConnectedAppsView: View {
    @Environment(AppModel.self) private var model
    @State private var rev = 0
    @State private var pairing: Pairing?
    @State private var target: PairingBody.For = .harbor
    @State private var making = false

    var body: some View {
        PageLoader(id: "\(rev)", load: { try await $0.devices() }) { list in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let pairing {
                        PairingPanel(pairing: pairing, target: target) { self.pairing = nil }
                    } else {
                        connect
                    }
                    DeviceGroup(list: list) { rev += 1 }
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .settingsPage("Connected apps")
        .task(id: pairing?.code) { await waitForPairing() }
    }

    private var connect: some View {
        SettingsGroup(label: "Connect",
                      footer: "Harbor can read and change your Anime, TV and Movies lists, nothing else. Another iPhone is signed in as you.") {
            Button { Task { await start(.harbor) } } label: {
                SettingsRow("Pair Harbor", symbol: "play.tv", sub: "Syncs what you watch, both ways", chevron: false, tint: true)
            }
            .buttonStyle(.plain)
            Button { Task { await start(.app) } } label: {
                SettingsRow("Connect another iPhone", symbol: "iphone", sub: "GupTrack on another phone", chevron: false,
                            separator: false, tint: true)
            }
            .buttonStyle(.plain)
        }
        .disabled(making)
    }

    private func start(_ t: PairingBody.For) async {
        making = true
        defer { making = false }
        switch await model.fetch({ try await $0.startPairing(for: t) }) {
        case .loaded(let p):
            target = t
            pairing = p
        case .failed(let why): model.notice = "Couldn't make a code: \(why)"
        case .loading: break
        }
    }

    /// ask every two seconds whether the code was used, until it runs out
    private func waitForPairing() async {
        guard let code = pairing?.code else { return }
        while !Task.isCancelled, let p = pairing, p.code == code, p.expires > Clock.now {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            guard case .loaded(let check) = await model.fetch({ try await $0.checkDevicePairing(code: code) }) else { continue }
            if let d = check.device {
                model.notice = "\(d.name) is connected."
                pairing = nil
                rev += 1
                return
            }
            if check.expired { return }
        }
    }
}

private struct PairingPanel: View {
    let pairing: Pairing
    let target: PairingBody.For
    var cancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(target == .harbor ? "Pair Harbor" : "Pair iPhone")
                .font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
            Text(target == .harbor
                 ? "In Harbor, open Settings, choose GupTrack and enter this code, or scan the QR with the phone Harbor is on."
                 : "In the GupTrack app on the other iPhone, choose Scan a code and point the camera at this QR, or type the code there.")
                .font(.system(size: 15)).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            SettingsQRCode(text: pairing.link)
                .frame(width: 168, height: 168)
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.top, 18)
                .accessibilityLabel("QR code for pairing code \(pairing.code)")
            Text(pairing.code)
                .font(.system(size: 30, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.ink)
                .kerning(2)
                .padding(.top, 16)
                .textSelection(.enabled)
            if target == .harbor {
                Text("Address: \(pairing.server)").font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
                    .textSelection(.enabled).padding(.top, 4)
            }
            TimelineView(.periodic(from: .now, by: 1)) { t in
                Text(pairing.expiryLine(now: t.date)).font(.system(size: 14)).foregroundStyle(Theme.inkMuted).numbers()
            }
            .padding(.top, 4)
            Button("Cancel", action: cancel).buttonStyle(.capsule(.tone, .small)).padding(.top, 14)
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
    let list: DeviceList
    var changed: () -> Void

    @Environment(AppModel.self) private var model
    @State private var dropping: Device?

    /// this iPhone first
    private var devices: [Device] { (list.this.map { [$0] } ?? []) + list.others }

    var body: some View {
        SettingsGroup(label: "Connected", footer: "Disconnecting signs that app out. Connect it again with a new code.") {
            ForEach(devices) { d in row(d) }
        }
        .confirmationDialog(dropping.map { "Disconnect \($0.name)?" } ?? "",
                            isPresented: Binding(get: { dropping != nil }, set: { if !$0 { dropping = nil } }),
                            titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { if let d = dropping { Task { await drop(d) } } }
            Button("Cancel", role: .cancel) { dropping = nil }
        } message: {
            Text("It stops syncing until you connect it again.")
        }
    }

    private func row(_ d: Device) -> some View {
        let mine = d.id == list.current
        return SettingsRow(d.name, symbol: d.symbol, sub: d.caption(), chevron: false,
                           separator: d.id != devices.last?.id) {
            if mine {
                SettingsLiveLabel(text: "This iPhone", live: true, size: 14)
            } else {
                Button("Disconnect") { dropping = d }
                    .buttonStyle(.capsule(.tone, .small, color: Theme.danger))
            }
        }
    }

    private func drop(_ d: Device) async {
        dropping = nil
        if let why = await model.fetch({ try await $0.disconnectDevice(d.id) }).error {
            model.notice = "Couldn't disconnect \(d.name): \(why)"
        } else {
            changed()
        }
    }
}

// MARK: 64 backups

/// what the Backups page shows: the backups kept before a restore, and the owner's nightly ones
private struct BackupsPage {
    var saved: [SavedBackup]
    var nightly: AutoBackupInfo?
}

/// a restore waiting for the OK
private enum PendingRestore: Identifiable {
    case nightly(AutoBackup)
    case saved(SavedBackup)
    case file(name: String, data: Data)

    var id: String {
        switch self {
        case .nightly(let b): return "n/" + b.name
        case .saved(let b): return "s/" + b.name
        case .file(let name, _): return "f/" + name
        }
    }

    var title: String {
        switch self {
        case .nightly(let b): return "Restore the backup from \(SettingsText.dayName(Millis.date(b.at)))?"
        case .saved(let b): return "Restore the backup from \(SettingsText.dayName(Millis.date(b.at)))?"
        case .file(let name, _): return "Restore \(name)?"
        }
    }
}

/// Settings › Backups (64): the nightly backups (owner), Back up now, the saved ones, restore from a file. Every
/// restore asks first, and keeps what you had as a saved backup.
struct BackupsView: View {
    @Environment(AppModel.self) private var model
    @State private var rev = 0
    @State private var restoring: PendingRestore?
    @State private var pickingFile = false
    @State private var working = false

    private var owner: Bool { model.account?.role == "owner" }

    var body: some View {
        PageLoader(id: "\(rev)", load: { [owner] api in
            async let saved = api.savedBackups()
            let nightly = owner ? try? await api.nightlyBackups() : nil
            return BackupsPage(saved: (try await saved).saved, nightly: nightly)
        }) { page in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let n = page.nightly { nightly(n) }
                    saved(page.saved)
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .settingsPage("Backups")
        .confirmationDialog(restoring?.title ?? "",
                            isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
                            titleVisibility: .visible) {
            Button("Restore", role: .destructive) { if let r = restoring { Task { await restore(r) } } }
            Button("Cancel", role: .cancel) { restoring = nil }
        } message: {
            Text("Your library goes back to how it was then. What you have now is kept under Saved backups first.")
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                restoring = .file(name: url.lastPathComponent, data: data)
            } else {
                model.notice = "Couldn't read that file."
            }
        }
    }

    private func nightly(_ info: AutoBackupInfo) -> some View {
        SettingsGroup(label: "Nightly backups", footer: nightlyFooter(info)) {
            SettingsToggleRow(label: "Back up every night", sub: "Kept on the PC GupTrack runs on",
                              isOn: Binding(get: { info.enabled }, set: { on in Task { await setNightly(on) } }))
            ForEach(info.backups) { b in
                Button { restoring = .nightly(b) } label: {
                    SettingsRow(SettingsText.dayName(Millis.date(b.at)) + ", " + Format.time(Millis.date(b.at)),
                                symbol: "clock.arrow.circlepath", value: SettingsText.size(b.size), chevron: false)
                }
                .buttonStyle(.plain)
            }
            Button { Task { await backUpNow() } } label: {
                SettingsRow("Back up now", symbol: "archivebox", chevron: false, separator: false, tint: true)
            }
            .buttonStyle(.plain)
            .disabled(working)
        }
    }

    private func nightlyFooter(_ info: AutoBackupInfo) -> String {
        var parts = ["Tap a backup to restore it."]
        if info.enabled, let next = info.nextAt {
            parts.append("The next one is \(SettingsText.dayName(Millis.date(next)).lowercased()) at \(Format.time(Millis.date(next))).")
        }
        return parts.joined(separator: " ")
    }

    private func saved(_ list: [SavedBackup]) -> some View {
        SettingsGroup(label: "Saved backups", footer: "GupTrack keeps your library as it was before each restore or reset.") {
            ForEach(list) { b in
                Button { restoring = .saved(b) } label: {
                    SettingsRow(b.label, symbol: "clock.arrow.circlepath",
                                value: SettingsText.dayName(Millis.date(b.at)), chevron: false)
                }
                .buttonStyle(.plain)
            }
            Button { pickingFile = true } label: {
                SettingsRow("Restore from a file", symbol: "doc", sub: "A guptrack-backup.json from Export", chevron: false,
                            separator: false, tint: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func setNightly(_ on: Bool) async {
        if let why = await model.fetch({ try await $0.setNightly(on) }).error {
            model.notice = "Couldn't change nightly backups: \(why)"
        }
        rev += 1
    }

    private func backUpNow() async {
        working = true
        defer { working = false }
        switch await model.fetch({ try await $0.backUpNow() }) {
        case .loaded(let a):
            if a.made == nil { model.notice = "Nothing has changed since the last backup." }
            rev += 1
        case .failed(let why): model.notice = "Couldn't back up: \(why)"
        case .loading: break
        }
    }

    private func restore(_ r: PendingRestore) async {
        restoring = nil
        let answer = await model.fetch { api -> RestoreAnswer in
            switch r {
            case .nightly(let b): return try await api.restoreNightly(b.name)
            case .saved(let b): return try await api.restoreSaved(b.name)
            case .file(_, let data): return try await api.restoreBackup(data)
            }
        }
        switch answer {
        case .loaded(let a):
            model.notice = a.line
            rev += 1
            await model.syncLibrary()
        case .failed(let why): model.notice = "Couldn't restore: \(why)"
        case .loading: break
        }
    }
}

// MARK: 64b accounts

/// Settings › Accounts (64b): the owner's page. Every account on this GupTrack, and invites to join.
struct AccountsSettingsView: View {
    @State private var rev = 0

    var body: some View {
        SettingsLoaded { s in
            if s.isOwner {
                PageLoader(id: "\(rev)", load: { try await $0.accounts() }) { a in AccountsList(answer: a) { rev += 1 } }
            } else {
                ContentUnavailableView("Only the owner can manage accounts", systemImage: "person.2.slash",
                                       description: Text("Ask the owner of this GupTrack for an invite."))
            }
        }
        .settingsPage("Accounts")
    }
}

private struct AccountsList: View {
    let answer: AccountsAnswer
    var changed: () -> Void

    @Environment(AppModel.self) private var model
    @State private var made: NewInvite?
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsGroup(label: answer.accounts.count == 1 ? "1 account" : "\(answer.accounts.count) accounts") {
                    ForEach(answer.accounts) { a in
                        SettingsRow(a.username, symbol: "person.crop.circle", sub: caption(a),
                                    value: a.role == "owner" ? "Owner" : "Member", chevron: false,
                                    separator: a.id != answer.accounts.last?.id)
                    }
                }
                if let made { NewInviteView(invite: made, base: model.account?.baseURL) }
                invites
            }
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
    }

    private func caption(_ a: AccountRow) -> String {
        let joined = "Joined " + Format.longDay(Millis.date(a.createdAt))
        guard a.sessions > 0 else { return joined }
        return joined + " · \(a.sessions) browser\(a.sessions == 1 ? "" : "s") signed in"
    }

    private var invites: some View {
        SettingsGroup(label: "Invites", footer: "An invite works once and runs out after a week. People who join only see what others share.") {
            ForEach(answer.invites) { i in
                SettingsRow("Invite from \(SettingsText.shortDate(Millis.date(i.createdAt)))", symbol: "envelope",
                            sub: i.state(), chevron: false) {
                    if i.isOpen() {
                        Button("Take back") { Task { await takeBack(i) } }
                            .buttonStyle(.capsule(.tone, .small, color: Theme.danger))
                    }
                }
            }
            Button { Task { await makeInvite() } } label: {
                SettingsRow("New invite", symbol: "link.badge.plus", chevron: false, separator: false, tint: true)
            }
            .buttonStyle(.plain)
            .disabled(working)
        }
    }

    private func makeInvite() async {
        working = true
        defer { working = false }
        switch await model.fetch({ try await $0.createInvite() }) {
        case .loaded(let i):
            changed()
            made = i
        case .failed(let why): model.notice = "Couldn't make an invite: \(why)"
        case .loading: break
        }
    }

    private func takeBack(_ i: Invite) async {
        if let why = await model.fetch({ try await $0.takeBackInvite(i.id) }).error {
            model.notice = "Couldn't take the invite back: \(why)"
        } else {
            changed()
        }
    }
}

/// the new invite's link, shown once
private struct NewInviteView: View {
    let invite: NewInvite
    let base: URL?

    var body: some View {
        let link = invite.link(on: base)
        VStack(alignment: .leading, spacing: 8) {
            Text("New invite").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(link).font(.system(size: 15, design: .monospaced)).foregroundStyle(Theme.inkSoft).textSelection(.enabled)
            Text("Send this link now: GupTrack won't show it again.").font(.system(size: 13)).foregroundStyle(Theme.inkMuted)
            HStack(spacing: 10) {
                ShareLink(item: link) { Label("Share", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.capsule(.tint, .small))
                Button { UIPasteboard.general.string = link } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(.capsule(.tone, .small))
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.bottom, 26)
    }
}
