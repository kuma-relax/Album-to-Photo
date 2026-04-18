import UIKit

extension UIImage {
    /// `imageOrientation` を `.up` に揃えた新しい `UIImage` を返す。
    /// カメラで撮影した `UIImage` は EXIF で向きが付くことが多く、
    /// そのまま CIImage などに渡すと座標系がズレるため、本メソッドで正規化する。
    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
}
