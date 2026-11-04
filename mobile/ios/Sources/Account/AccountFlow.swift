import SwiftUI
import UIKit

/// Signed out (01-04): connect to a server, sign in, join, recovery codes. The flow's state and calls are
/// AccountFlowModel (GupTrackKit/AccountFlowLogic.swift); RootView shows the tabs once the model is signed in.
struct AccountFlow: View {
    @Environment(AppModel.self) private var model
    @State private var flow: AccountFlowModel?

    var body: some View {
        Group {
            if let flow {
                AccountStack(flow: flow)
            } else {
                Theme.sheet.ignoresSafeArea()
            }
        }
        .onAppear {
            guard flow == nil else { return }
            flow = AccountFlowModel(model: model, start: model.accountScreen, server: lastServer,
                                    device: model.isDemo ? "Mika's iPhone" : UIDevice.current.name)
        }
    }

    /// the server signed in to last time (kept so signing back in doesn't ask for it again)
    private var lastServer: URL? {
        if model.isDemo { return Demo.server }
        return UserDefaults.standard.string(forKey: AccountStack.lastServerKey).flatMap(PairLink.serverURL)
    }
}

/// the flow's stack: connect or sign-in at the bottom, join and recover pushed over sign-in
struct AccountStack: View {
    @Bindable var flow: AccountFlowModel

    static let lastServerKey = "account.lastServer"

    var body: some View {
        NavigationStack(path: $flow.path) {
            AccountScreen(step: flow.root, flow: flow)
                .navigationDestination(for: AccountFlowModel.Step.self) { step in
                    AccountScreen(step: step, flow: flow)
                }
        }
        .preferredColorScheme(.dark)
        .onChange(of: flow.server) { _, server in
            guard !flow.model.isDemo, let server else { return }
            UserDefaults.standard.set(server.absoluteString, forKey: Self.lastServerKey)
        }
        // a pairing link opened from the Camera app
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "guptrack", url.host?.lowercased() == "pair" else { return }
            Task {
                if let problem = await flow.pair(url.absoluteString) { flow.model.notice = problem }
            }
        }
    }
}

/// one step's screen
struct AccountScreen: View {
    let step: AccountFlowModel.Step
    let flow: AccountFlowModel

    var body: some View {
        switch step {
        case .connect: ConnectServerView(flow: flow)
        case .signIn: SignInView(flow: flow)
        case .join: JoinView(flow: flow)
        case .recover: RecoverView(flow: flow)
        case .codes: RecoveryCodesView(flow: flow)
        }
    }
}

// MARK: shared parts (design/iphone/screens/_account.mjs)

/// A form field as the mockups draw it: a label over a hairline-outlined 50pt box (brand outline when focused),
/// an optional icon, the input, something on the right, and a help line under it.
struct AccountField<Input: View, Trailing: View>: View {
    let label: String
    var symbol: String?
    var focused = false
    var help: Text?
    @ViewBuilder var input: () -> Input
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkMuted)
                .padding(.leading, 2)
                .padding(.bottom, 7)
            box
            if let help {
                help
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
                    .padding(.top, 7)
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.bottom, 16)
    }

    private var box: some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(width: 22)
                    .accessibilityHidden(true)
            }
            input()
                .font(.system(size: 17))
                .foregroundStyle(Theme.ink)
                .tint(Theme.brand)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(focused ? Theme.brand : Color.white.opacity(0.16), lineWidth: focused ? 1.5 : 0.5)
        }
    }
}

extension AccountField where Trailing == EmptyView {
    init(_ label: String, symbol: String? = nil, focused: Bool = false, help: Text? = nil,
         @ViewBuilder input: @escaping () -> Input) {
        self.init(label: label, symbol: symbol, focused: focused, help: help, input: input, trailing: { EmptyView() })
    }
}

/// a password input with Show / Hide on the right (the field's trailing part)
struct AccountPasswordInput<F: Hashable>: View {
    @Binding var text: String
    var focus: FocusState<F?>.Binding
    let value: F
    var newPassword = false
    var submit: () -> Void = {}
    @Binding var shown: Bool

    var body: some View {
        Group {
            if shown {
                TextField("", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                SecureField("", text: $text)
            }
        }
        .textContentType(newPassword ? UITextContentType.newPassword : UITextContentType.password)
        .submitLabel(.go)
        .onSubmit(submit)
        .focused(focus, equals: value)
        .accessibilityLabel("Password")
    }
}

/// Show / Hide for a password field
struct AccountShowButton: View {
    @Binding var shown: Bool

    var body: some View {
        Button(shown ? "Hide" : "Show") { shown.toggle() }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.brandSoft)
            .buttonStyle(.plain)
    }
}

/// a divider with a word in the middle ("or")
struct AccountOrRule: View {
    var word = "or"

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Theme.sep).frame(height: 0.5)
            Text(word).font(.system(size: 13)).foregroundStyle(Theme.inkMuted).fixedSize()
            Rectangle().fill(Theme.sep).frame(height: 0.5)
        }
        .padding(.horizontal, Theme.pad)
    }
}

/// the 52pt brand-tinted tile with a symbol over a screen's title
struct AccountIconTile: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(Theme.brandSoft)
            .frame(width: 52, height: 52)
            .background(Theme.brand.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// "New here? Join GupTrack": muted words and a brand link, centred
struct AccountLinkLine: View {
    let lead: String
    let link: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            (Text(lead).foregroundStyle(Theme.inkMuted)
                + Text(link).foregroundStyle(Theme.brandSoft).fontWeight(.semibold))
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

/// a call's error, under the main button
struct AccountErrorLine: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.danger)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.pad)
                .padding(.top, 12)
        }
    }
}

/// the label of a main button: its title, or a spinner while the call runs
struct AccountBusyLabel: View {
    let title: String
    let busy: Bool

    var body: some View {
        ZStack {
            Text(title).opacity(busy ? 0 : 1)
            if busy { ProgressView().tint(.white) }
        }
    }
}

extension Theme {
    /// the green of "Found GupTrack", the strong meter and the username check
    static let accountGood = Theme.color(.current)
}

/// the four-part strength meter under a new password, with "Strong · 18 characters"
struct AccountPasswordMeter: View {
    let meter: PasswordMeter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i < meter.lit ? color : Theme.track)
                        .frame(height: 3)
                }
            }
            Text(meter.label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .numbers()
        }
        .padding(.horizontal, 22)
        .padding(.top, -6)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch meter.tone {
        case "good": return Theme.accountGood
        case "star": return Theme.star
        case "danger": return Theme.danger
        default: return Theme.track
        }
    }
}
