import Foundation
import UIKit

/// 1 枚のアルバムページ。撮影した原本と検出された写真の集合を持つ。
struct AlbumPage: Identifiable {
    let id: UUID
    /// 撮影した原本画像（向き補正済み）。
    var sourceImage: UIImage
    /// 検出された写真の矩形一覧。
    var detections: [DetectedPhoto]

    init(id: UUID = UUID(), sourceImage: UIImage, detections: [DetectedPhoto] = []) {
        self.id = id
        self.sourceImage = sourceImage
        self.detections = detections
    }
}
