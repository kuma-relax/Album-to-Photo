import Foundation
import Photos
import UIKit

/// 切り出した写真を iOS 写真ライブラリに書き出す。
struct PhotoLibraryService {

    enum SaveError: Error, LocalizedError {
        case notAuthorized
        case saveFailed(Error)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "写真ライブラリへのアクセスが許可されていません。設定アプリから許可してください。"
            case .saveFailed(let error):
                return "写真の保存に失敗しました: \(error.localizedDescription)"
            }
        }
    }

    /// ユーザーに「追加」権限をリクエストする。
    func requestAddOnlyAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// 1 枚の画像を写真ライブラリに保存する。
    func save(image: UIImage) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let effective: PHAuthorizationStatus
        switch status {
        case .notDetermined:
            effective = await requestAddOnlyAuthorization()
        default:
            effective = status
        }

        guard effective == .authorized || effective == .limited else {
            throw SaveError.notAuthorized
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else if let error {
                    continuation.resume(throwing: SaveError.saveFailed(error))
                } else {
                    continuation.resume(throwing: SaveError.saveFailed(NSError(
                        domain: "AlbumToPhoto.PhotoLibraryService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Unknown save error"]
                    )))
                }
            }
        }
    }

    /// 複数枚をまとめて保存する。
    func save(images: [UIImage]) async throws {
        for image in images {
            try await save(image: image)
        }
    }
}
