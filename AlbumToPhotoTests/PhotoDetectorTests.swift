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
}
