import SwiftUI
import VisionKit

/// VisionKit の DataScanner を SwiftUI で使う
struct BarcodeScannerView: UIViewControllerRepresentable {
    var isActive: Bool
    var onCode: (String) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false
        )
        controller.delegate = context.coordinator
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        context.coordinator.isActive = isActive
        if isActive {
            if !controller.isScanning {
                // 画面に乗る前だと失敗することがあるので次のループで開始する
                DispatchQueue.main.async {
                    guard context.coordinator.isActive, !controller.isScanning else { return }
                    try? controller.startScanning()
                }
            }
        } else if controller.isScanning {
            controller.stopScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        var isActive = true
        private var lastCode: String?
        private var lastTime = Date.distantPast

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(updatedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item])
        }

        private func handle(_ items: [RecognizedItem]) {
            guard isActive else { return }
            for item in items {
                guard case .barcode(let barcode) = item, let payload = barcode.payloadStringValue else { continue }
                // 同じコードを短時間で何度も拾わない
                if payload == lastCode, Date().timeIntervalSince(lastTime) < 2.5 { return }
                lastCode = payload
                lastTime = Date()
                onCode(payload)
                return
            }
        }
    }
}
