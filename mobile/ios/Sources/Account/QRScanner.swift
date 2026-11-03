import AVFoundation
import SwiftUI
import UIKit

/// The camera looking for a QR code (AVCaptureMetadataOutput), for the website's pairing code. Asks for the camera
/// the first time (NSCameraUsageDescription); says how to allow it when it was turned down. Only on a real iPhone.
struct QRScanner: View {
    let found: (String) -> Void

    @State private var allowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var denied = false

    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return AVCaptureDevice.default(for: .video) != nil
        #endif
    }

    var body: some View {
        Group {
            if allowed {
                QRCameraView(found: found)
            } else if denied {
                VStack(spacing: 12) {
                    Text("GupTrack can't use the camera.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkMuted)
                    Button("Allow it in Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.capsule(.tone, .small))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black)
        .task {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                allowed = true
            case .notDetermined:
                let ok = await AVCaptureDevice.requestAccess(for: .video)
                allowed = ok
                denied = !ok
            default:
                denied = true
            }
        }
    }
}

/// the camera preview and the QR reader
struct QRCameraView: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> QRCameraController {
        let c = QRCameraController()
        c.found = found
        return c
    }

    func updateUIViewController(_ controller: QRCameraController, context: Context) {
        controller.found = found
    }
}

final class QRCameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var found: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    /// the last code handed on (the camera sees the same code many times a second)
    private var last: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let s = session
        // startRunning blocks, so not on the main thread
        DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let s = session
        DispatchQueue.global(qos: .utility).async { s.stopRunning() }
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        guard let text = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first
        else { return }
        // the delegate queue is the main queue
        MainActor.assumeIsolated { self.deliver(text) }
    }

    private func deliver(_ text: String) {
        guard text != last else { return }
        last = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        found?(text)
    }
}
