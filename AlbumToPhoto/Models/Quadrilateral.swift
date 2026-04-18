import CoreGraphics
import Foundation

/// 画像空間における 4 点の四角形。
/// 座標は UIKit 座標系（左上原点・pt）で、元画像のピクセル座標を想定する。
struct Quadrilateral: Equatable, Hashable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    /// 軸整列された矩形から正方形状の Quadrilateral を作る。
    init(rect: CGRect) {
        self.topLeft = CGPoint(x: rect.minX, y: rect.minY)
        self.topRight = CGPoint(x: rect.maxX, y: rect.minY)
        self.bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        self.bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
    }

    init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    /// 4 点を包含する軸整列バウンディングボックス。
    var boundingBox: CGRect {
        let xs = [topLeft.x, topRight.x, bottomRight.x, bottomLeft.x]
        let ys = [topLeft.y, topRight.y, bottomRight.y, bottomLeft.y]
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 4 点の面積（Shoelace formula）。
    var area: CGFloat {
        let points = [topLeft, topRight, bottomRight, bottomLeft]
        var sum: CGFloat = 0
        for i in 0..<points.count {
            let current = points[i]
            let next = points[(i + 1) % points.count]
            sum += current.x * next.y - next.x * current.y
        }
        return abs(sum) / 2.0
    }

    /// アフィン変換を適用した Quadrilateral を返す。
    func applying(_ transform: CGAffineTransform) -> Quadrilateral {
        Quadrilateral(
            topLeft: topLeft.applying(transform),
            topRight: topRight.applying(transform),
            bottomRight: bottomRight.applying(transform),
            bottomLeft: bottomLeft.applying(transform)
        )
    }
}
