import SwiftUI

/// 02 Sign in: username and password, or a recovery code (passkeys are website-only for now);
/// shows the server it talks to, with Change.
struct SignInView: View {
    @Bindable var flow: AccountFlowModel

    private enum Field: Hashable { case username, password }
    @FocusState private var focus: Field?
    @State private var shown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                form.padding(.top, 37)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { footer }
        .pageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task { await flow.loadServer() }
        .onAppear {
            // the demo fills in the demo user so it signs in with one tap
            if flow.model.isDemo && flow.password.isEmpty {
                if flow.username.isEmpty { flow.username = "mika" }
                flow.password = "demo-password"
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("GupTrack")
                .font(.system(size: 40, weight: .heavy))
                .kerning(-1.8)
                .foregroundStyle(Theme.ink)
            Text("Sign in to your library.")
                .font(.system(size: 17))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 10)
            serverLine.padding(.top, 8)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 88)
    }

    private var serverLine: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.accountGood).frame(width: 7, height: 7)
            Text(flow.server.map(ServerCheck.display) ?? "No server")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkMuted)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Change") { flow.changeServer() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.brandSoft)
                .buttonStyle(.plain)
                .accessibilityLabel("Change server")
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            AccountField("Username", symbol: "person", focused: focus == .username) {
                TextField("", text: $flow.username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                    .focused($focus, equals: .username)
                    .accessibilityLabel("Username")
            }
            AccountField(label: "Password", symbol: "lock", focused: focus == .password) {
                AccountPasswordInput(text: $flow.password, focus: $focus, value: Field.password,
                                     submit: { Task { await flow.signIn() } }, shown: $shown)
            } trailing: {
                AccountShowButton(shown: $shown)
            }
            Button {
                focus = nil
                Task { await flow.signIn() }
            } label: {
                AccountBusyLabel(title: "Sign in", busy: flow.busy)
            }
            .buttonStyle(.capsule(.tint, .large, full: true))
            .disabled(!flow.canSignIn)
            .padding(.horizontal, Theme.pad)
            .padding(.top, 8)
            AccountErrorLine(text: flow.error)
            AccountLinkLine(lead: "Forgot your password? ", link: "Use a recovery code") { flow.go(.recover) }
                .padding(.top, 24)
        }
    }

    @ViewBuilder private var footer: some View {
        if flow.canJoinHere {
            AccountLinkLine(lead: "New here? ", link: "Join GupTrack") { flow.go(.join) }
                .padding(.bottom, 10)
                .padding(.top, 8)
                .frame(maxWidth: .infinity)
                .background(Theme.sheet)
        }
    }
}
