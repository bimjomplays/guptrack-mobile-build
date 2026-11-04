import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: account

/// Settings › Account: how you sign in. The password, recovery codes, the passkeys (added on the website only), the
/// browsers signed in, and signing out everywhere.
struct AccountPageView: View {
    @Environment(AppModel.self) private var model
    @State private var rev = 0
    @State private var changingPassword = false
    @State private var askingForCodes = false
    @State private var codesPassword = ""
    @State private var newCodes: [String]?
    @State private var leaving = false

    var body: some View {
        PageLoader(id: "\(rev)", load: { try await $0.account() }) { info in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    signIn(info)
                    recovery(info)
                    sessions(info)
                    signOutEverywhere
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .settingsPage("Account")
        .sheet(isPresented: $changingPassword) { ChangePasswordSheet() }
        .sheet(isPresented: Binding(get: { newCodes != nil }, set: { if !$0 { newCodes = nil; rev += 1 } })) {
            NewCodesSheet(codes: newCodes ?? [], username: model.account?.user.username ?? "",
                          server: model.account?.baseURL)
        }
        .alert("Make new recovery codes", isPresented: $askingForCodes) {
            SecureField("Password", text: $codesPassword)
            Button("Cancel", role: .cancel) { codesPassword = "" }
            Button("Make codes") { Task { await makeCodes() } }
        } message: {
            Text("Type your password. The codes you have now stop working.")
        }
        .confirmationDialog("Sign out everywhere?", isPresented: $leaving, titleVisibility: .visible) {
            Button("Sign out everywhere", role: .destructive) { Task { await signOutEverywhere() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every browser and app is signed out, this iPhone too.")
        }
    }

    private func signIn(_ info: AccountInfo) -> some View {
        SettingsGroup(label: "Sign-in", footer: "Passkeys are added and removed in Settings › Account on the website.") {
            SettingsRow("Signed in as", value: "@" + info.username, chevron: false)
            Button { changingPassword = true } label: { SettingsRow("Change password", symbol: "key") }
                .buttonStyle(.plain)
            SettingsRow("Passkeys", symbol: "person.badge.key", value: info.passkeyLine, chevron: false, separator: false)
        }
    }

    private func recovery(_ info: AccountInfo) -> some View {
        SettingsGroup(label: "Recovery codes", footer: recoveryFooter(info)) {
            SettingsRow("Codes left", symbol: "list.number", value: info.recoveryLine, chevron: false)
            Button { askingForCodes = true } label: {
                SettingsRow(info.recovery.total == 0 ? "Make codes" : "Make new codes", chevron: false, separator: false,
                            tint: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func recoveryFooter(_ info: AccountInfo) -> String {
        let r = info.recovery
        if r.total > 0 && r.left == 0 { return "None left. Make new ones and keep them somewhere safe." }
        if r.total > 0 && r.left <= 3 { return "Running low. Make new ones and keep them somewhere safe." }
        return "If you forget your password, a recovery code sets a new one."
    }

    private func sessions(_ info: AccountInfo) -> some View {
        SettingsGroup(label: "Browsers signed in", footer: info.sessions.isEmpty ? "No browsers are signed in." : nil) {
            ForEach(info.sessions) { s in
                SettingsRow(s.name, symbol: "globe", sub: s.current ? "This browser" : s.seenLine(), chevron: false,
                            separator: s.id != info.sessions.last?.id) {
                    Button("Sign out") { Task { await end(s) } }
                        .buttonStyle(.capsule(.tone, .small, color: Theme.danger))
                }
            }
        }
    }

    private var signOutEverywhere: some View {
        SettingsGroup {
            Button { leaving = true } label: {
                SettingsRow("Sign out everywhere", symbol: "rectangle.portrait.and.arrow.right", chevron: false,
                            separator: false, danger: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func makeCodes() async {
        let password = codesPassword
        codesPassword = ""
        switch await model.fetch({ try await $0.newRecoveryCodes(password: password) }) {
        case .loaded(let a): newCodes = a.codes
        case .failed(let why): model.notice = "Couldn't make new codes: \(why)"
        case .loading: break
        }
    }

    private func end(_ s: SessionInfo) async {
        if let why = await model.fetch({ try await $0.endSession(s.id) }).error {
            model.notice = "Couldn't sign that browser out: \(why)"
        } else {
            rev += 1
        }
    }

    private func signOutEverywhere() async {
        if let why = await model.fetch({ try await $0.signOutEverywhere() }).error {
            model.notice = "Couldn't sign out everywhere: \(why)"
            return
        }
        await model.signOut()
    }
}

/// the new password: the current one, the new one twice
private struct ChangePasswordSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var next = ""
    @State private var again = ""
    @State private var error: String?
    @State private var working = false

    private var ready: Bool { !current.isEmpty && next.count >= 15 && next == again && !working }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsGroup(footer: footer) {
                        field("Current password", text: $current, content: .password)
                        field("New password", text: $next, content: .newPassword)
                        field("New password again", text: $again, content: .newPassword, last: true)
                    }
                }
                .padding(.top, 8)
            }
            .pageBackground()
            .navigationTitle("Change password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Change") { Task { await change() } }.disabled(!ready)
                }
            }
        }
    }

    private var footer: String {
        if let error { return error }
        if !again.isEmpty && next != again { return "The new passwords don't match." }
        return "At least 15 characters. A few words in a row work well. Every browser and app is signed out; this iPhone stays signed in."
    }

    private func field(_ label: String, text: Binding<String>, content: UITextContentType, last: Bool = false) -> some View {
        SecureField(label, text: text)
            .textContentType(content)
            .font(.system(size: 17))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.pad)
            .frame(minHeight: 52)
            .overlay(alignment: .bottom) { if !last { Hairline().padding(.leading, Theme.pad) } }
    }

    private func change() async {
        guard let server = model.account?.baseURL else { return }
        working = true
        defer { working = false }
        error = nil
        do {
            let answer = try await model.api.changePassword(current: current, next: next)
            await model.signedIn(answer, server: server)
            model.notice = "Password changed. Every other browser and app was signed out."
            dismiss()
        } catch let e as APIError where e.code == "wrong_password" {
            error = "That isn't your current password."
        } catch let e as APIError {
            error = e.message
        } catch {
            self.error = "Couldn't reach your GupTrack."
        }
    }
}

/// the new recovery codes, shown once: copy or save them
private struct NewCodesSheet: View {
    let codes: [String]
    let username: String
    let server: URL?

    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false
    @State private var copied = false

    private var text: String {
        server.map { RecoveryCodes.text(codes, username: username, server: $0) } ?? codes.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your new codes. The old ones no longer work, and GupTrack won't show these again.")
                        .font(.system(size: 15)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.pad).padding(.bottom, 16)
                    SettingsGroup {
                        ForEach(Array(codes.enumerated()), id: \.offset) { i, code in
                            HStack(spacing: 14) {
                                Text("\(i + 1)").font(.system(size: 13)).foregroundStyle(Theme.inkMuted).frame(width: 22)
                                    .numbers()
                                Text(code).font(.system(size: 17, design: .monospaced)).foregroundStyle(Theme.ink)
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Theme.pad)
                            .frame(minHeight: 44)
                            .overlay(alignment: .bottom) {
                                if i < codes.count - 1 { Hairline().padding(.leading, Theme.pad) }
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = text
                            copied = true
                        } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                            .buttonStyle(.capsule(.tone, .regular, full: true))
                        Button { exporting = true } label: { Label("Save to Files", systemImage: "folder") }
                            .buttonStyle(.capsule(.tone, .regular, full: true))
                    }
                    .padding(.horizontal, Theme.pad)
                }
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .pageBackground()
            .navigationTitle("Recovery codes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileExporter(isPresented: $exporting, document: RecoveryCodesFile(text: text), contentType: .plainText,
                          defaultFilename: RecoveryCodes.fileName(username: username)) { _ in }
        }
        .interactiveDismissDisabled()
    }
}
