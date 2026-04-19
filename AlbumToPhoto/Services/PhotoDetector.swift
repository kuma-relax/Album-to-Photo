import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit
import Vision

/// アルバム 1 ページの画像から、貼り付けられている個々の写真の矩形を検出する。
///
/// 内部では `VNDetectRectanglesRequest` を複数パラメータで実行（マルチパス検出）し、
/// 前処理（コントラスト強調）で透明フィルムの反射による輪郭ボケを補うことで、
/// 単発検出よりも取りこぼしを減らすことを狙う。
/// Vision の正規化座標 (左下原点) は UIKit 座標系 (左上原点・pt) に変換したうえで
/// `DetectedPhoto` として返す。
struct PhotoDetector {

    /// 単一の検出パスで使うパラメータ。
    struct PassConfiguration {
        var minimumAspectRatio: Float
        var maximumAspectRatio: Float
        var minimumSize: Float
        var maximumObservations: Int
        var minimumConfidence: VNConfidence
        var quadratureTolerance: Float

        /// 一般的な写真サイズ向けの標準パス。
        static let balanced = PassConfiguration(
            minimumAspectRatio: 0.3,
            maximumAspectRatio: 1.0 / 0.3,
            minimumSize: 0.05,
            maximumObservations: 32,
            minimumConfidence: 0.5,
            quadratureTolerance: 45
        )

        /// 小さい写真や端のほうに寄った写真も拾うためのパス。
        /// 以前は 0.35 / 0.03 まで緩めていたが、写真内部の顔や被写体の矩形を
        /// 拾ってしまうため、控えめな値に戻している。
        static let permissive = PassConfiguration(
            minimumAspectRatio: 0.25,
            maximumAspectRatio: 1.0 / 0.25,
            minimumSize: 0.05,
            maximumObservations: 32,
            minimumConfidence: 0.48,
            quadratureTolerance: 45
        )
    }

    /// `PhotoDetector` 全体の設定。
    struct Configuration {
        /// 実行する検出パスのリスト。順に実行され、結果は重複除去でマージされる。
        var passes: [PassConfiguration]
        /// 重複除去のしきい値（IoU）。これ以上重なっていれば同一矩形とみなす。
        var duplicateIoUThreshold: CGFloat = 0.45
        /// 包含関係に基づく重複除去のしきい値。小さい矩形が大きい矩形に
        /// この割合以上含まれている場合、写真内部の誤検出とみなして除去する。
        /// 1.0 に設定するとこのロジックは無効化される。
        var containmentThreshold: CGFloat = 0.8
        /// 包含関係による除去を行う際、2 つの矩形の面積比がこれ以上離れている
        /// 場合のみ除去対象にする。誤って同程度のサイズの写真を潰さないため。
        var containmentAreaRatio: CGFloat = 1.5
        /// コントラスト強調の前処理を有効にするかどうか。
        var enableContrastPreprocessing: Bool = true
        /// 前処理で用いるコントラスト倍率。1.0 で無変化。
        /// 強めると輪郭は立つが、写真内部のエッジまで強調されて誤検出の原因になる。
        var preprocessingContrast: Double = 1.1
        /// 前処理で用いる彩度倍率（低めにして輪郭のコントラストを優先）。
        var preprocessingSaturation: Double = 0.9

        /// 標準構成: balanced + permissive の 2 パスで取りこぼしを抑え、
        /// 包含関係チェックで写真内部の誤検出を落とす。
        static let `default` = Configuration(
            passes: [.balanced, .permissive]
        )

        /// permissive を外した保守的な構成。過剰検出が目立つ場合のフォールバック用。
        static let balancedOnly = Configuration(
            passes: [.balanced]
        )
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
    private let ciContext: CIContext

    init(
        configuration: Configuration = .default,
        ciContext: CIContext = CIContext(options: [.useSoftwareRenderer: false])
    ) {
        self.configuration = configuration
        self.ciContext = ciContext
    }

    // MARK: - Public API

    /// 指定画像から写真矩形を検出する。
    /// - Parameter image: `imageOrientation` が `.up` に正規化された `UIImage` を想定。
    /// - Returns: 検出された `DetectedPhoto` の配列。面積の降順。
    func detect(in image: UIImage) async throws -> [DetectedPhoto] {
        guard let originalCGImage = image.cgImage else {
            throw DetectionError.missingCGImage
        }

        let imageSize = CGSize(width: originalCGImage.width, height: originalCGImage.height)

        // 前処理 (コントラスト強調)。Vision に渡すのは前処理後の CGImage。
        let processedCGImage: CGImage = {
            guard configuration.enableContrastPreprocessing else { return originalCGImage }
            return preprocessedCGImage(from: originalCGImage) ?? originalCGImage
        }()

        var allDetections: [DetectedPhoto] = []
        for pass in configuration.passes {
            let detections = try runPass(
                pass,
                cgImage: processedCGImage,
                imageSize: imageSize
            )
            allDetections.append(contentsOf: detections)
        }

        let deduplicated = Self.deduplicate(
            detections: allDetections,
            iouThreshold: configuration.duplicateIoUThreshold,
            containmentThreshold: configuration.containmentThreshold,
            containmentAreaRatio: configuration.containmentAreaRatio
        )

        return deduplicated.sorted { $0.quad.area > $1.quad.area }
    }

    // MARK: - Single pass

    private func runPass(
        _ pass: PassConfiguration,
        cgImage: CGImage,
        imageSize: CGSize
    ) throws -> [DetectedPhoto] {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = pass.minimumAspectRatio
        request.maximumAspectRatio = pass.maximumAspectRatio
        request.minimumSize = pass.minimumSize
        request.maximumObservations = pass.maximumObservations
        request.minimumConfidence = pass.minimumConfidence
        request.quadratureTolerance = pass.quadratureTolerance

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw DetectionError.visionFailed(error)
        }

        let observations = request.results ?? []
        return observations.map { observation in
            let quad = Self.quadrilateral(from: observation, imageSize: imageSize)
            return DetectedPhoto(quad: quad, confidence: observation.confidence)
        }
    }

    // MARK: - Preprocessing

    /// 透明フィルムの反射や退色で輪郭がボケた写真でも Vision が検出しやすいよう、
    /// コントラストを少し上げた CGImage を作って返す。
    private func preprocessedCGImage(from cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)

        let filter = CIFilter.colorControls()
        filter.inputImage = ciImage
        filter.contrast = Float(configuration.preprocessingContrast)
        filter.saturation = Float(configuration.preprocessingSaturation)
        filter.brightness = 0

        guard let output = filter.outputImage else { return nil }
        return ciContext.createCGImage(output, from: output.extent)
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
    /// 後方互換のため残している。
    static func deduplicate(
        detections: [DetectedPhoto],
        iouThreshold: CGFloat
    ) -> [DetectedPhoto] {
        deduplicate(
            detections: detections,
            iouThreshold: iouThreshold,
            containmentThreshold: 1.0,
            containmentAreaRatio: 1.0
        )
    }

    /// IoU + 包含関係による重複除去。
    /// - Parameters:
    ///   - iouThreshold: 2 つの矩形を同一とみなす IoU のしきい値。
    ///   - containmentThreshold: 小さい矩形が大きい矩形に含まれる割合のしきい値。
    ///     例えば 0.8 なら、小さい矩形が大きい矩形の 80% 以上に収まっていれば
    ///     写真内部の誤検出として除去する。 1.0 を指定すると無効化される。
    ///   - containmentAreaRatio: 包含関係を使って除去する際の面積比しきい値。
    ///     大きい矩形の面積がこの倍以上でなければ除去しない（同サイズに近い矩形
    ///     同士を潰さないガード）。
    static func deduplicate(
        detections: [DetectedPhoto],
        iouThreshold: CGFloat,
        containmentThreshold: CGFloat,
        containmentAreaRatio: CGFloat
    ) -> [DetectedPhoto] {
        // 信頼度の高い順に採用していく従来の IoU ベース重複除去。
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

        // 包含関係ベースの除去。小さい矩形が大きい矩形に含まれているなら削除する。
        // 信頼度の順序は保ったまま "大きい方" を残したいので、面積で比較する。
        guard containmentThreshold < 1.0 else { return kept }
        var survivors: [DetectedPhoto] = []
        for (index, candidate) in kept.enumerated() {
            let candidateArea = candidate.quad.area
            guard candidateArea > 0 else { continue }
            let candidateBox = candidate.quad.boundingBox
            let isInsideLarger = kept.enumerated().contains { otherIndex, other in
                guard otherIndex != index else { return false }
                let otherArea = other.quad.area
                guard otherArea > 0 else { return false }
                // candidate が other より大きい、または同程度のサイズなら除去対象外。
                guard otherArea >= candidateArea * containmentAreaRatio else { return false }
                return candidateBox.containmentRatio(inside: other.quad.boundingBox) >= containmentThreshold
            }
            if !isInsideLarger {
                survivors.append(candidate)
            }
        }
        return survivors
    }
}
