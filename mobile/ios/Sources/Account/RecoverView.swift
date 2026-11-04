import SwiftUI

/// "Use a recovery code" from Sign in (no mockup; drawn like Join): username, one recovery code, a new password.
/// Signs this iPhone in with the new password (POST auth/recover).
struct RecoverView: View {
    @Bindable var flow: AccountFlowModel

    private enum Field: Hashable { case username, code, password }
    @FocusState private var focus: Field?
    @State private var shown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                fields.padding(.top, 34)
                AccountPasswordMeter(meter: flow.meter)
                Button {
                    focus = nil
                    Task { await flow.recover() }
                } label: {
                    AccountBusyLabel(title: "Set password and sign in", busy: flow.busy)
                }
                .buttonStyle(.capsule(.tint, .large, full: true))
                .disabled(!flow.canRecover)
                .padding(.horizontal, Theme.pad)
                .padding(.top, 26)
                AccountErrorLine(text: flow.error)
            }
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .pageBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Use a recovery code")
                .font(.system(size: 34, weight: .bold))
                .kerning(-1)
                .foregroundStyle(Theme.ink)
            Text("One of the codes you saved when you joined sets a new password. Each code works once.")
                .font(.system(size: 17))
                .lineSpacing(3)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 4)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 0) {
            AccountField("Username", symbol: "person", focused: focus == .username) {
                TextField("", text: $flow.username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focus = .code }
                    .focused($focus, equals: .username)
                    .accessibilityLabel("Username")
            }
            AccountField("Recovery code", symbol: "key", focused: focus == .code) {
                TextField("", text: $flow.code)
                    .font(.system(size: 17, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                    .focused($focus, equals: .code)
                    .accessibilityLabel("Recovery code")
            }
            AccountField(label: "New password", symbol: "lock", focused: focus == .password) {
                AccountPasswordInput(text: $flow.password, focus: $focus, value: Field.password, newPassword: true,
                                     submit: { Task { await flow.recover() } }, shown: $shown)
            } trailing: {
                AccountShowButton(shown: $shown)
            }
        }
    }
}
