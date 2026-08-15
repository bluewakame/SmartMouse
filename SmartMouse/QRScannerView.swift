import AVFoundation
import SwiftUI

struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onCancel: () -> Void
    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController(); controller.onScan = onScan; controller.onCancel = onCancel; return controller
    }
    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didScan = false

    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        let title = UILabel(); title.text = "WindowsのQRコードを枠内に合わせてください"; title.textColor = .white
        title.font = .preferredFont(forTextStyle: .headline); title.textAlignment = .center; title.numberOfLines = 0
        let cancel = UIButton(type: .system); cancel.setTitle("キャンセル", for: .normal)
        cancel.titleLabel?.font = .preferredFont(forTextStyle: .headline); cancel.addTarget(self, action: #selector(cancelScan), for: .touchUpInside)
        [title, cancel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), title.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            cancel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24), cancel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async { if granted { self?.configureCamera() } else { self?.onCancel?() } }
        }
    }

    private func configureCamera() {
        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else { return }
        session.addInput(input); let output = AVCaptureMetadataOutput(); guard session.canAddOutput(output) else { return }
        session.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
        let preview = AVCaptureVideoPreviewLayer(session: session); preview.videoGravity = .resizeAspectFill; preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0); previewLayer = preview
        DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
    }

    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); previewLayer?.frame = view.bounds }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !didScan, let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject, let value = object.stringValue else { return }
        didScan = true; session.stopRunning(); UINotificationFeedbackGenerator().notificationOccurred(.success); onScan?(value)
    }
    @objc private func cancelScan() { session.stopRunning(); onCancel?() }
}
