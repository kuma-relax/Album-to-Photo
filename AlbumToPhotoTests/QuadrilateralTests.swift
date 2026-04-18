import XCTest
@testable import AlbumToPhoto

final class QuadrilateralTests: XCTestCase {

    func testBoundingBoxFromRect() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
        let quad = Quadrilateral(rect: rect)
        XCTAssertEqual(quad.boundingBox, rect)
    }

    func testAreaOfAxisAlignedRect() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let quad = Quadrilateral(rect: rect)
        XCTAssertEqual(quad.area, 200 * 100, accuracy: 0.001)
    }

    func testApplyingScaleTransform() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        let quad = Quadrilateral(rect: rect)
        let scaled = quad.applying(CGAffineTransform(scaleX: 2, y: 3))
        XCTAssertEqual(scaled.topLeft, CGPoint(x: 0, y: 0))
        XCTAssertEqual(scaled.topRight, CGPoint(x: 20, y: 0))
        XCTAssertEqual(scaled.bottomRight, CGPoint(x: 20, y: 30))
        XCTAssertEqual(scaled.bottomLeft, CGPoint(x: 0, y: 30))
    }
}
