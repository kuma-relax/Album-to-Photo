import SwiftUI
import VisionKit

/// `VNDocumentCameraViewController` を SwiftUI でラップしたスキャナ画面。
///
/// VisionKit 標準のドキュメントスキャナは、ページのエッジ検出と
/// 遠近補正を OS 側で行ってくれるため、アルバムページの撮影に適している。
struct DocumentScannerView: UIViewControllerRepresentable {

    typealias Completion = (Result<[UIImage], Error>) -> Void

    let completion: Completion

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let completion: Completion
        init(completion: @escaping Completion) {
            self.completion = completion
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var images: [UIImage] = []
            for index in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: index))
            }
            completion(.success(images))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            completion(.success([]))
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            completion(.failure(error))
        }
    }
}
