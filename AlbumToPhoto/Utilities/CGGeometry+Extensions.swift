import CoreGraphics
import Foundation

extension CGPoint {
    /// 2 点間のユークリッド距離。
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// 定数倍。
    static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
}

extension CGRect {
    /// 2 つの矩形の Intersection over Union。
    func iou(with other: CGRect) -> CGFloat {
        let intersection = self.intersection(other)
        if intersection.isNull || intersection.isEmpty { return 0 }
        let unionArea = width * height + other.width * other.height - intersection.width * intersection.height
        guard unionArea > 0 else { return 0 }
        return (intersection.width * intersection.height) / unionArea
    }
}
