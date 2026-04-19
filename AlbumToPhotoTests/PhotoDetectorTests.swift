import XCTest
@testable import AlbumToPhoto

final class PhotoDetectorTests: XCTestCase {

    func testDeduplicateRemovesOverlappingLowerConfidence() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let overlappingRect = CGRect(x: 5, y: 5, width: 100, height: 100)
        let farRect = CGRect(x: 500, y: 500, width: 100, height: 100)

        let high = DetectedPhoto(quad: Quadrilateral(rect: rect), confidence: 0.9)
        let low = DetectedPhoto(quad: Quadrilateral(rect: overlappingRect), confidence: 0.7)
        let far = DetectedPhoto(quad: Quadrilateral(rect: farRect), confidence: 0.65)

        let result = PhotoDetector.deduplicate(
            detections: [low, high, far],
            iouThreshold: 0.35
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains(where: { $0.id == high.id }))
        XCTAssertTrue(result.contains(where: { $0.id == far.id }))
        XCTAssertFalse(result.contains(where: { $0.id == low.id }))
    }

    func testDeduplicateKeepsAllDisjointRects() {
        let rects = (0..<4).map { i in
            CGRect(x: CGFloat(i) * 200, y: 0, width: 100, height: 100)
        }
        let detections = rects.enumerated().map { index, rect in
            DetectedPhoto(quad: Quadrilateral(rect: rect), confidence: Float(0.9 - Double(index) * 0.1))
        }

        let result = PhotoDetector.deduplicate(detections: detections, iouThreshold: 0.35)
        XCTAssertEqual(result.count, detections.count)
    }

    /// マルチパス検出で同じ矩形が複数パスから得られても、重複除去で 1 つに集約されること。
    func testDeduplicateMergesMultiPassDetectionsOfSameRect() {
        let sharedRect = CGRect(x: 10, y: 10, width: 100, height: 150)
        let onlyInPermissive = CGRect(x: 400, y: 400, width: 80, height: 80)

        let balancedPassResult = [
            DetectedPhoto(quad: Quadrilateral(rect: sharedRect), confidence: 0.85)
        ]
        let permissivePassResult = [
            DetectedPhoto(quad: Quadrilateral(rect: sharedRect), confidence: 0.55),
            DetectedPhoto(quad: Quadrilateral(rect: onlyInPermissive), confidence: 0.45)
        ]

        let merged = PhotoDetector.deduplicate(
            detections: balancedPassResult + permissivePassResult,
            iouThreshold: 0.45
        )

        XCTAssertEqual(merged.count, 2, "共通の矩形は 1 つに集約し、permissive 独自の検出は残るはず")
        // 信頼度の高い方 (balanced 側, 0.85) が残る
        XCTAssertTrue(merged.contains { abs($0.confidence - 0.85) < 0.001 })
        // permissive 独自の矩形も残る
        XCTAssertTrue(merged.contains { $0.quad.boundingBox.origin.x == 400 })
    }

    /// Configuration.default が単一パス + 前処理 OFF + 包含関係除去 OFF で構成されていること。
    /// 実機検証で安定していた初期値に準じる。
    func testDefaultConfigurationIsSinglePassConservative() {
        let config = PhotoDetector.Configuration.default
        XCTAssertEqual(config.passes.count, 1)
        XCTAssertFalse(config.enableContrastPreprocessing)
        XCTAssertEqual(config.duplicateIoUThreshold, 0.35, accuracy: 0.0001)
        XCTAssertEqual(config.containmentThreshold, 1.0, accuracy: 0.0001, "包含関係除去は無効")
    }

    /// balanced パスが初期のしきい値に戻っていること。
    func testBalancedPassUsesInitialThresholds() {
        let pass = PhotoDetector.PassConfiguration.balanced
        XCTAssertEqual(pass.minimumSize, 0.08, accuracy: 0.0001)
        XCTAssertEqual(pass.maximumObservations, 16)
        XCTAssertEqual(pass.minimumConfidence, 0.6, accuracy: 0.0001)
        XCTAssertEqual(pass.quadratureTolerance, 20, accuracy: 0.0001)
    }

    /// balancedOnly が default と同じ単一パス構成なこと。
    func testBalancedOnlyConfiguration() {
        let config = PhotoDetector.Configuration.balancedOnly
        XCTAssertEqual(config.passes.count, 1)
        XCTAssertFalse(config.enableContrastPreprocessing)
    }

    /// multiPass が 2 パス + 前処理 + 包含除去有効になっていること。
    func testMultiPassConfiguration() {
        let config = PhotoDetector.Configuration.multiPass
        XCTAssertEqual(config.passes.count, 2)
        XCTAssertTrue(config.enableContrastPreprocessing)
        XCTAssertEqual(config.duplicateIoUThreshold, 0.45, accuracy: 0.0001)
        XCTAssertLessThan(config.containmentThreshold, 1.0, "包含除去が有効")
    }

    /// 大きい矩形の内部に収まった小さい矩形が、包含関係ベースの重複除去で落とされること。
    /// `multiPass` が依存している挙動なので引き続き検証する。
    func testDeduplicateRemovesInnerRectContainedInLargerRect() {
        let bigRect = CGRect(x: 0, y: 0, width: 400, height: 300)
        let faceRect = CGRect(x: 50, y: 50, width: 80, height: 80)
        let disjointRect = CGRect(x: 600, y: 600, width: 200, height: 150)

        let detections = [
            DetectedPhoto(quad: Quadrilateral(rect: bigRect), confidence: 0.9),
            DetectedPhoto(quad: Quadrilateral(rect: faceRect), confidence: 0.75),
            DetectedPhoto(quad: Quadrilateral(rect: disjointRect), confidence: 0.85)
        ]

        let result = PhotoDetector.deduplicate(
            detections: detections,
            iouThreshold: 0.45,
            containmentThreshold: 0.8,
            containmentAreaRatio: 1.5
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains(where: { $0.quad.boundingBox == bigRect }))
        XCTAssertTrue(result.contains(where: { $0.quad.boundingBox == disjointRect }))
        XCTAssertFalse(result.contains(where: { $0.quad.boundingBox == faceRect }))
    }

    /// 面積 0 の矩形は包含関係チェックで黙って落とされず、そのまま残ること。
    /// (Devin Review 指摘: 以前は guard で continue していたため silently dropped)
    func testDeduplicateKeepsZeroAreaDetectionsWhenContainmentEnabled() {
        let zeroAreaRect = CGRect(x: 100, y: 100, width: 0, height: 0)
        let normalRect = CGRect(x: 0, y: 0, width: 200, height: 150)

        let detections = [
            DetectedPhoto(quad: Quadrilateral(rect: normalRect), confidence: 0.9),
            DetectedPhoto(quad: Quadrilateral(rect: zeroAreaRect), confidence: 0.8)
        ]

        let result = PhotoDetector.deduplicate(
            detections: detections,
            iouThreshold: 0.45,
            containmentThreshold: 0.8,
            containmentAreaRatio: 1.5
        )

        XCTAssertEqual(result.count, 2, "面積 0 の矩形も残す")
        XCTAssertTrue(result.contains(where: { $0.quad.boundingBox == normalRect }))
        XCTAssertTrue(result.contains(where: { $0.quad.area == 0 }))
    }

    /// `containmentThreshold = 1.0` で包含関係ロジックが無効化されること。
    func testDeduplicateDisablesContainmentWhenThresholdIsOne() {
        let bigRect = CGRect(x: 0, y: 0, width: 400, height: 300)
        let faceRect = CGRect(x: 50, y: 50, width: 80, height: 80)

        let detections = [
            DetectedPhoto(quad: Quadrilateral(rect: bigRect), confidence: 0.9),
            DetectedPhoto(quad: Quadrilateral(rect: faceRect), confidence: 0.75)
        ]

        let result = PhotoDetector.deduplicate(
            detections: detections,
            iouThreshold: 0.45,
            containmentThreshold: 1.0,
            containmentAreaRatio: 1.5
        )

        XCTAssertEqual(result.count, 2)
    }
}
