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

    /// Configuration.default が balanced + permissive の 2 パスで構成されていること。
    func testDefaultConfigurationHasBothPasses() {
        let config = PhotoDetector.Configuration.default
        XCTAssertEqual(config.passes.count, 2)
        XCTAssertTrue(config.enableContrastPreprocessing)
        XCTAssertEqual(config.duplicateIoUThreshold, 0.45, accuracy: 0.0001)
    }

    /// balancedOnly が permissive パスを含まないこと。
    func testBalancedOnlyConfiguration() {
        let config = PhotoDetector.Configuration.balancedOnly
        XCTAssertEqual(config.passes.count, 1)
    }

    /// 大きい写真矩形の中に収まった小さい矩形（= 写真内部の誤検出）が除去されること。
    func testDeduplicateRemovesInnerRectContainedInLargerRect() {
        let bigRect = CGRect(x: 0, y: 0, width: 400, height: 300) // 写真全体
        let faceRect = CGRect(x: 50, y: 50, width: 80, height: 80) // 写真内部の顔など
        let disjointRect = CGRect(x: 600, y: 600, width: 200, height: 150) // 別の写真

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

        XCTAssertEqual(result.count, 2, "写真内部の小さい矩形は除去され、残りは 2 つ")
        XCTAssertTrue(result.contains(where: { $0.quad.boundingBox == bigRect }))
        XCTAssertTrue(result.contains(where: { $0.quad.boundingBox == disjointRect }))
        XCTAssertFalse(result.contains(where: { $0.quad.boundingBox == faceRect }))
    }

    /// 面積がほぼ同じなら包含関係があっても除去しない (面積比ガード)。
    func testDeduplicateKeepsSimilarSizedRectsEvenIfOverlapping() {
        // 面積比 1.05 倍程度のほぼ同サイズ。位置もわずかにズレているだけ。
        let rectA = CGRect(x: 0, y: 0, width: 100, height: 100)
        let rectB = CGRect(x: 5, y: 5, width: 95, height: 95) // A の中に入っているが面積差が小さい

        let detections = [
            DetectedPhoto(quad: Quadrilateral(rect: rectA), confidence: 0.9),
            DetectedPhoto(quad: Quadrilateral(rect: rectB), confidence: 0.88)
        ]

        // IoU が高いので IoU ベースの重複除去で 1 つになるはずだが、
        // ここでは IoU しきい値を上げて「IoU では同一とみなされないが包含関係はある」
        // 状況をシミュレートする。
        let result = PhotoDetector.deduplicate(
            detections: detections,
            iouThreshold: 0.99, // 事実上 IoU で重複除去は起きない
            containmentThreshold: 0.8,
            containmentAreaRatio: 1.5 // A は B の 1.05 倍なので除去条件を満たさない
        )

        XCTAssertEqual(result.count, 2, "面積比が小さい矩形同士は除去しない")
    }

    /// containmentThreshold = 1.0 で包含関係ロジックを無効化できること。
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
            containmentThreshold: 1.0, // 無効化
            containmentAreaRatio: 1.5
        )

        XCTAssertEqual(result.count, 2)
    }
}
