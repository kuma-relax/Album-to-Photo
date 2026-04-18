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
}
