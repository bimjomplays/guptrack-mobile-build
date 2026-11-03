import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 04 Recovery codes, shown once after joining: Copy, Save to Files, the "I've saved these" tick, Open GupTrack
/// (which signs in with the new account).
struct RecoveryCodesView: View {
    @Bindable var flow: AccountFlowModel

    @State private var copied = false
    @State private var exporting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if flow.codes.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    codeGrid.padding(.top, 22)
                    buttons.padding(.top, 18)
                    savedCheck.padding(.top, 22)
                }
            }
            .padding(.horizontal, Theme.pad)
        }
        .safeAreaInset(edge: .bottom) { footer }
        .pageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .interactiveDismissDisabled()
        .task {
            // the demo's -account recovery: make the demo account to have codes to show
            if flow.model.isDemo && flow.codes.isEmpty { await flow.demoJoin() }
        }
        .fileExporter(isPresented: $exporting, document: RecoveryCodesFile(text: flow.codesText),
                      contentType: .plainText,
                      defaultFilename: RecoveryCodes.fileName(username: flow.joinedUsername)) { _ in }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            AccountIconTile(symbol: "key")
            Text("Save your recovery codes")
                .font(.system(size: 30, weight: .bold))
                .kerning(-0.9)
                .foregroundStyle(Theme.ink)
                .padding(.top, 18)
            Text("If you forget your password, one of these gets you back in. Each code works once. GupTrack won't show them again.")
                .font(.system(size: 16))
                .lineSpacing(3)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .padding(.top, 40)
    }

    private var codeGrid: some View {
        let columns = RecoveryCodes.columns(flow.codes)
        let grid = Array(repeating: GridItem(.flexible(), spacing: 0), count: columns)
        return LazyVGrid(columns: grid, spacing: 0) {
            ForEach(Array(flow.codes.enumerated()), id: \.offset) { i, code in
                CodeCell(number: i + 1, code: code, divider: columns == 2 && i % 2 == 0, big: columns == 2)
            }
        }
        .padding(.vertical, 8)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recovery codes")
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button {
                UIPasteboard.general.string = flow.codesText
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.capsule(.tone, full: true))
            Button {
                exporting = true
            } label: {
                Label("Save to Files", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.capsule(.tone, full: true))
        }
    }

    private var savedCheck: some View {
        Button {
            flow.saved.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(flow.saved ? Theme.brand : Color.clear)
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(flow.saved ? Theme.brand : Theme.inkFaint, lineWidth: 1.5)
                    if flow.saved {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 24, height: 24)
                .padding(.top, 1)
                Text("I've saved these somewhere safe, away from this PC.")
                    .font(.system(size: 16))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I've saved these somewhere safe")
        .accessibilityAddTraits(flow.saved ? .isSelected : [])
    }

    private var footer: some View {
        Button {
            Task { await flow.finishJoining() }
        } label: {
            Text("Open GupTrack")
        }
        .buttonStyle(.capsule(.tint, .large, full: true))
        .disabled(!flow.saved)
        .opacity(flow.saved ? 1 : 0.45)
        .padding(.horizontal, Theme.pad)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Theme.sheet)
    }
}

/// one numbered code; the left column has the hairline between the columns
private struct CodeCell: View {
    let number: Int
    let code: String
    let divider: Bool
    let big: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
                .frame(width: 16, alignment: .leading)
            Text(code)
                .font(.system(size: big ? 18 : 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, big ? 20 : 16)
        // the long codes go one to a line, close together so all ten, Copy and the tick fit on the screen (04)
        .padding(.vertical, big ? 14 : 6)
        .overlay(alignment: .trailing) {
            if divider { Rectangle().fill(Theme.sep).frame(width: 0.5) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// the codes as a text file for Save to Files
struct RecoveryCodesFile: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
