import CoreImage
import Foundation
import UIKit
import Vision

/// アルバム 1 ページの画像から、貼り付けられている個々の写真の矩形を検出する。
///
/// 内部では `VNDetectRectanglesRequest` を利用し、Vision の正規化座標 (左下原点)
/// を UIKit 座標系 (左上原点・pt) に変換したうえで `DetectedPhoto` として返す。
struct PhotoDetector {

    /// 検出パラメータ。チューニングしやすいように構造体として切り出しておく。
    struct Configuration {
        /// 写真の最小アスペクト比（短辺/長辺）。0.3 で 1:3 の縦横比まで許容。
        var minimumAspectRatio: Float = 0.3
        /// 写真の最小サイズ（画像短辺に対する比率）。
        var minimumSize: Float = 0.08
        /// 最大検出数。アルバム 1 ページは通常 2〜8 枚程度。
        var maximumObservations = 16
        /// 最低信頼度。
        var minimumConfidence: VNConfidence = 0.6
        /// 矩形統合のしきい値（IoU）。これ以上重なっていれば重複とみなす。
        var duplicateIoUThreshold: CGFloat = 0.35

        static let `default` = Configuration()
    }

    enum DetectionError: Error, LocalizedError {
        case missingCGImage
        case visionFailed(Error)

        var errorDescription: String? {
            switch self {
            case .missingCGImage:
                return "画像データを取得できませんでした。"
            case .visionFailed(let error):
                return "画像解析に失敗しました: \(error.localizedDescription)"
            }
        }
    }

    var configuration: Configuration = .default

    /// 指定画像から写真矩形を検出する。
    /// - Parameter image: `imageOrientation` が `.up` に正規化された `UIImage` を想定。
    /// - Returns: 検出された `DetectedPhoto` の配列。面積の降順。
    func detect(in image: UIImage) async throws -> [DetectedPhoto] {
        guard let cgImage = image.cgImage else {
            throw DetectionError.missingCGImage
        }

        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = configuration.minimumAspectRatio
        request.maximumAspectRatio = 1.0 / configuration.minimumAspectRatio
        request.minimumSize = configuration.minimumSize
        request.maximumObservations = configuration.maximumObservations
        request.minimumConfidence = configuration.minimumConfidence
        request.quadratureTolerance = 20

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw DetectionError.visionFailed(error)
        }

        let observations = request.results ?? []
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        let converted = observations.map { observation -> DetectedPhoto in
            let quad = Self.quadrilateral(from: observation, imageSize: imageSize)
            return DetectedPhoto(quad: quad, confidence: observation.confidence)
        }

        let deduplicated = Self.deduplicate(
            detections: converted,
            iouThreshold: configuration.duplicateIoUThreshold
        )

        // 面積の降順でソート
        return deduplicated.sorted { $0.quad.area > $1.quad.area }
    }

    // MARK: - Helpers

    /// Vision の観測結果 (正規化・左下原点) を UIKit 座標 (pt・左上原点) に変換する。
    static func quadrilateral(
        from observation: VNRectangleObservation,
        imageSize: CGSize
    ) -> Quadrilateral {
        func convert(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: point.x * imageSize.width,
                y: (1.0 - point.y) * imageSize.height
            )
        }
        return Quadrilateral(
            topLeft: convert(observation.topLeft),
            topRight: convert(observation.topRight),
            bottomRight: convert(observation.bottomRight),
            bottomLeft: convert(observation.bottomLeft)
        )
    }

    /// IoU による重複除去。同じ領域を指している矩形のうち、信頼度が高い方を残す。
    static func deduplicate(
        detections: [DetectedPhoto],
        iouThreshold: CGFloat
    ) -> [DetectedPhoto] {
        // 信頼度の降順にソートし、既に採用済みの矩形と IoU がしきい値を超えるものを捨てる。
        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var kept: [DetectedPhoto] = []
        for candidate in sorted {
            let candidateBox = candidate.quad.boundingBox
            let isDuplicate = kept.contains { existing in
                existing.quad.boundingBox.iou(with: candidateBox) >= iouThreshold
            }
            if !isDuplicate {
                kept.append(candidate)
            }
        }
        return kept
    }
}
