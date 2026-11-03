import SwiftUI

/// 01 Connect to your GupTrack: scan the website's pairing code, or type the server's address (checked as you type)
/// and name this iPhone; Continue goes on to signing in there.
struct ConnectServerView: View {
    @Bindable var flow: AccountFlowModel

    private enum Field: Hashable { case address, device }
    @FocusState private var focus: Field?
    @State private var scanning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                scanCard
                    .padding(.horizontal, Theme.pad)
                    .padding(.top, 26)
                AccountOrRule(word: "or enter it yourself")
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                addressField
                deviceField
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { footer }
        .pageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $scanning) { ScanPairingSheet(flow: flow) }
        // checks the address a moment after typing stops
        .task(id: flow.address) {
            if case .checking = ServerCheck.parse(flow.address) {
                try? await Task.sleep(nanoseconds: flow.model.isDemo ? 0 : 600_000_000)
                guard !Task.isCancelled else { return }
            }
            await flow.checkAddress()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            AccountIconTile(symbol: "macbook.and.iphone")
            Text("Connect to your GupTrack")
                .font(.system(size: 30, weight: .bold))
                .kerning(-0.9)
                .foregroundStyle(Theme.ink)
                .padding(.top, 18)
            Text("GupTrack runs on your PC. This iPhone reaches it over Tailscale, at home or away.")
                .font(.system(size: 16))
                .lineSpacing(3)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 66)
    }

    private var scanCard: some View {
        Button {
            scanning = true
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "qrcode")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(.black)
                    .frame(width: 64, height: 64)
                    .background(Color(hex: 0xF5F5F7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scan the pairing code")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("On the website, open Settings › Connected apps › Connect an iPhone.")
                        .font(.system(size: 14))
                        .lineSpacing(2)
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
            }
            .multilineTextAlignment(.leading)
            .padding(18)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scan the pairing code")
    }

    private var addressField: some View {
        AccountField(label: "Server address", symbol: "server.rack", focused: focus == .address, help: addressHelp) {
            TextField("", text: $flow.address, prompt: Text("Your PC's Tailscale name").foregroundStyle(Theme.inkFaint))
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focus = .device }
                .focused($focus, equals: .address)
                .accessibilityLabel("Server address")
        } trailing: {
            addressStatus
        }
    }

    @ViewBuilder private var addressStatus: some View {
        switch flow.check {
        case .checking:
            ProgressView().controlSize(.small)
        case .found:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.accountGood)
                .accessibilityLabel("Found GupTrack")
        case .invalid, .wrong, .unreachable:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.danger)
                .accessibilityHidden(true)
        case .empty:
            EmptyView()
        }
    }

    private var addressHelp: Text {
        let help = flow.check.help
        if let good = help.good {
            return Text(good).foregroundStyle(Theme.accountGood) + Text(help.text).foregroundStyle(Theme.inkMuted)
        }
        return Text(help.text).foregroundStyle(help.problem ? Theme.danger : Theme.inkMuted)
    }

    private var deviceField: some View {
        AccountField("This device", symbol: "iphone", focused: focus == .device,
                     help: Text("Listed under Connected devices on the website.")) {
            TextField("", text: $flow.device, prompt: Text("iPhone").foregroundStyle(Theme.inkFaint))
                .textContentType(.name)
                .submitLabel(.done)
                .focused($focus, equals: .device)
                .accessibilityLabel("This device")
        }
    }

    private var footer: some View {
        VStack(spacing: 16) {
            Button {
                focus = nil
                flow.useCheckedServer()
            } label: {
                Text("Continue")
            }
            .buttonStyle(.capsule(.tint, .large, full: true))
            .disabled(!flow.canContinue)
            .opacity(flow.canContinue ? 1 : 0.45)
            AccountLinkLine(lead: "or ", link: "sign in with username and password") {
                focus = nil
                flow.useCheckedServer()
            }
            .disabled(flow.check.server == nil)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Theme.sheet)
    }
}

/// The pairing code: the camera on an iPhone, and a field to paste the link (the simulator and the demo have no
/// camera, so they show a plain placeholder there).
struct ScanPairingSheet: View {
    let flow: AccountFlowModel

    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var problem: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    camera
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .padding(.horizontal, Theme.pad)
                        .padding(.top, 8)
                    Text("On the website, open Settings › Connected apps › Connect an iPhone, and point the camera at the code.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.pad)
                        .padding(.top, 12)
                    AccountOrRule(word: "or paste the link")
                        .padding(.vertical, 18)
                    linkField
                    if let problem {
                        Text(problem)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Theme.pad)
                    }
                }
            }
            .pageBackground()
            .navigationTitle("Pairing code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { Task { await use(link) } }
                        .accessibilityLabel("Connect")
                        .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || flow.busy)
                }
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var camera: some View {
        if QRScanner.isAvailable && !flow.model.isDemo {
            QRScanner { text in Task { await use(text) } }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.inkMuted)
                Text("The camera isn't available here.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
            }
        }
    }

    private var linkField: some View {
        AccountField("Pairing link", symbol: "link", focused: focused) {
            TextField("", text: $link, prompt: Text("guptrack://pair?…").foregroundStyle(Theme.inkFaint))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { Task { await use(link) } }
                .focused($focused)
                .accessibilityLabel("Pairing link")
        }
    }

    private func use(_ text: String) async {
        problem = nil
        if let p = await flow.pair(text) {
            problem = p
        } else {
            dismiss()
        }
    }
}
