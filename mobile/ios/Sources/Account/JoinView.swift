import SwiftUI

/// 03 Join GupTrack: a new account on the server (username with its rule, display name, password with a strength
/// meter, and the invite code when the server wants one). Next come the recovery codes.
struct JoinView: View {
    @Bindable var flow: AccountFlowModel

    private enum Field: Hashable { case invite, username, name, password }
    @FocusState private var focus: Field?
    @State private var shown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                fields.padding(.top, 41)
                AccountPasswordMeter(meter: flow.meter)
                Button {
                    focus = nil
                    Task { await flow.join() }
                } label: {
                    AccountBusyLabel(title: "Create account", busy: flow.busy)
                }
                .buttonStyle(.capsule(.tint, .large, full: true))
                .disabled(!flow.canJoin)
                .padding(.horizontal, Theme.pad)
                .padding(.top, 26)
                AccountErrorLine(text: flow.error)
                Text("Next you'll get recovery codes, in case you ever forget your password.")
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 40)
                    .padding(.top, 14)
            }
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            AccountLinkLine(lead: "Have an account? ", link: "Sign in") { flow.go(.signIn) }
                .padding(.bottom, 10)
                .padding(.top, 8)
                .frame(maxWidth: .infinity)
                .background(Theme.sheet)
        }
        .pageBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await flow.loadServer()
            // the server's answer says whether joining needs an invite
            if flow.model.isDemo && flow.needsInvite && flow.invite.isEmpty { flow.invite = "demo-invite" }
        }
        .onAppear {
            // the demo fills in an invented new account
            // (field by field: the username may already be there from an earlier sign-in)
            if flow.model.isDemo && flow.password.isEmpty {
                if flow.username.isEmpty { flow.username = "mika" }
                if flow.displayName.isEmpty { flow.displayName = "Mika" }
                flow.password = "demo-Paper-lantern"
                if flow.needsInvite && flow.invite.isEmpty { flow.invite = "demo-invite" }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Join GupTrack")
                .font(.system(size: 34, weight: .bold))
                .kerning(-1)
                .foregroundStyle(Theme.ink)
            Text("Make your account. Your library, profile and settings are your own.")
                .font(.system(size: 17))
                .lineSpacing(3)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 4)
    }

    @ViewBuilder private var fields: some View {
        VStack(alignment: .leading, spacing: 0) {
            if flow.needsInvite { inviteField }
            usernameField
            AccountField("Display name", focused: focus == .name,
                         help: Text("Shown on your profile. You can change it later.")) {
                TextField("", text: $flow.displayName)
                    .textContentType(.nickname)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                    .focused($focus, equals: .name)
                    .accessibilityLabel("Display name")
            }
            AccountField(label: "Password", symbol: "lock", focused: focus == .password) {
                AccountPasswordInput(text: $flow.password, focus: $focus, value: Field.password, newPassword: true,
                                     submit: { Task { await flow.join() } }, shown: $shown)
            } trailing: {
                AccountShowButton(shown: $shown)
            }
        }
    }

    private var inviteField: some View {
        AccountField("Invite code", symbol: "ticket", focused: focus == .invite,
                     help: Text("From the owner of this GupTrack (Settings › Accounts on the website).")) {
            TextField("", text: $flow.invite)
                .textContentType(.oneTimeCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focus = .username }
                .focused($focus, equals: .invite)
                .accessibilityLabel("Invite code")
        }
    }

    private var usernameField: some View {
        let rule = flow.usernameRule
        return AccountField(label: "Username", symbol: "person", focused: focus == .username,
                            help: Text(rule.message).foregroundStyle(rule.isProblem ? Theme.danger : Theme.inkMuted)) {
            TextField("", text: $flow.username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focus = .name }
                .focused($focus, equals: .username)
                .accessibilityLabel("Username")
        } trailing: {
            if rule == .ok {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.accountGood)
                    .accessibilityLabel("Username is fine")
            }
        }
    }
}
