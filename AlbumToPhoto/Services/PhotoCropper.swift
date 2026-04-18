import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

/// 検出された 4 点の矩形（Quadrilateral）をもとに、元画像から遠近補正付きでクロップする。
struct PhotoCropper {

    private let ciContext: CIContext

    init(ciContext: CIContext = CIContext(options: [.useSoftwareRenderer: false])) {
        self.ciContext = ciContext
    }

    enum CropError: Error, LocalizedError {
        case missingCIImage
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .missingCIImage:
                return "画像からクロップ用データを生成できませんでした。"
            case .renderFailed:
                return "クロップ画像の生成に失敗しました。"
            }
        }
    }

    /// 元画像 (UIKit 座標・左上原点) から、与えられた Quadrilateral で切り出す。
    /// - Important: `sourceImage.imageOrientation` は `.up` を前提とする。
    func crop(sourceImage: UIImage, quad: Quadrilateral) throws -> UIImage {
        guard let ciImage = CIImage(image: sourceImage) else {
            throw CropError.missingCIImage
        }

        // CoreImage は Vision と同じく左下原点の座標系を使うため、y を反転する。
        let imageHeight = sourceImage.size.height
        func toCoreImage(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x, y: imageHeight - p.y)
        }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = ciImage
        filter.topLeft = toCoreImage(quad.topLeft)
        filter.topRight = toCoreImage(quad.topRight)
        filter.bottomLeft = toCoreImage(quad.bottomLeft)
        filter.bottomRight = toCoreImage(quad.bottomRight)

        guard let output = filter.outputImage else {
            throw CropError.renderFailed
        }

        guard let cgImage = ciContext.createCGImage(output, from: output.extent) else {
            throw CropError.renderFailed
        }

        return UIImage(cgImage: cgImage, scale: sourceImage.scale, orientation: .up)
    }
}
