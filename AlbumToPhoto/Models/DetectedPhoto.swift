import Foundation
import UIKit

/// アルバムページ内で検出された 1 枚の写真。
struct DetectedPhoto: Identifiable, Equatable {
    let id: UUID
    /// 元ページ画像の座標系 (UIKit: 左上原点・pt) における 4 点。
    var quad: Quadrilateral
    /// Vision の信頼度 (0...1)。手動追加の矩形の場合は 1.0 固定。
    var confidence: Float
    /// クロップ後画像。プレビュー/書き出し時に遅延生成される。
    var croppedImage: UIImage?
    /// 書き出し済みかどうか。
    var isExported: Bool

    init(
        id: UUID = UUID(),
        quad: Quadrilateral,
        confidence: Float,
        croppedImage: UIImage? = nil,
        isExported: Bool = false
    ) {
        self.id = id
        self.quad = quad
        self.confidence = confidence
        self.croppedImage = croppedImage
        self.isExported = isExported
    }
}
