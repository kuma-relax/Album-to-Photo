import Foundation
import SwiftUI
import UIKit

/// 検出結果の状態管理。UI からの操作（検出実行・矩形編集・保存）を担当する。
@MainActor
@Observable
final class DetectionResultViewModel {

    enum Phase: Equatable {
        case idle
        case detecting
        case ready
        case saving
        case failed(String)
    }

    private(set) var page: AlbumPage
    private(set) var phase: Phase = .idle
    /// 保存完了時に true を 1 回だけ流すトリガ。
    private(set) var saveCompletedToastID: UUID?

    private let detector: PhotoDetector
    private let cropper: PhotoCropper
    private let library: PhotoLibraryService

    init(
        page: AlbumPage,
        detector: PhotoDetector = PhotoDetector(),
        cropper: PhotoCropper = PhotoCropper(),
        library: PhotoLibraryService = PhotoLibraryService()
    ) {
        self.page = page
        self.detector = detector
        self.cropper = cropper
        self.library = library
    }

    // MARK: - Detection

    /// 写真矩形を検出する。初回表示時に呼び出す想定。
    func runDetectionIfNeeded() async {
        guard case .idle = phase else { return }
        phase = .detecting
        do {
            let detections = try await detector.detect(in: page.sourceImage)
            page.detections = detections
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Editing

    func updateQuad(for detectionID: UUID, to newQuad: Quadrilateral) {
        guard let index = page.detections.firstIndex(where: { $0.id == detectionID }) else { return }
        page.detections[index].quad = newQuad
        // Quad が変わったのでクロップ済み画像は無効化する。
        page.detections[index].croppedImage = nil
        page.detections[index].isExported = false
    }

    func removeDetection(id: UUID) {
        page.detections.removeAll { $0.id == id }
    }

    func addDetectionAtCenter() {
        let size = page.sourceImage.size
        let rect = CGRect(
            x: size.width * 0.25,
            y: size.height * 0.25,
            width: size.width * 0.5,
            height: size.height * 0.5
        )
        let quad = Quadrilateral(rect: rect)
        page.detections.append(DetectedPhoto(quad: quad, confidence: 1.0))
    }

    // MARK: - Cropping

    /// プレビュー用にクロップ画像を作って差し込む（まだ生成されていない場合のみ）。
    func ensureCroppedImage(for detectionID: UUID) {
        guard let index = page.detections.firstIndex(where: { $0.id == detectionID }) else { return }
        guard page.detections[index].croppedImage == nil else { return }
        do {
            let cropped = try cropper.crop(
                sourceImage: page.sourceImage,
                quad: page.detections[index].quad
            )
            page.detections[index].croppedImage = cropped
        } catch {
            // クロップ失敗は UI 側で個別にリカバリ可能にするため、ここでは握り潰さず phase を壊さない。
            page.detections[index].croppedImage = nil
        }
    }

    // MARK: - Export

    /// 全ての検出結果を写真ライブラリに保存する。
    func saveAllToPhotoLibrary() async {
        phase = .saving
        do {
            var images: [UIImage] = []
            for index in page.detections.indices {
                if page.detections[index].croppedImage == nil {
                    let cropped = try cropper.crop(
                        sourceImage: page.sourceImage,
                        quad: page.detections[index].quad
                    )
                    page.detections[index].croppedImage = cropped
                }
                if let image = page.detections[index].croppedImage {
                    images.append(image)
                }
            }

            try await library.save(images: images)

            for index in page.detections.indices {
                page.detections[index].isExported = true
            }
            phase = .ready
            saveCompletedToastID = UUID()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
