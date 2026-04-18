# Album to Photo — 企画・設計ドキュメント

> 昔ながらの透明フィルム式アルバム（台紙に写真を貼り、上から透明フィルムで押さえるタイプ）の
> 1 ページを丸ごと撮影し、**貼り付けられている写真を 1 枚ずつ自動で切り出す** iOS アプリ。

---

## 1. 背景と目的

- 実家のアルバムをデジタル化したいが、1 枚ずつ剥がしてスキャンするのは大変。
- 台紙ごとスマホで撮影 →アプリで各写真の領域を検出して **自動クロップ** すれば、1 ページ数秒で取り込める。
- さらに、透明フィルムによる反射や歪みをある程度補正することで、そのまま鑑賞できる品質を目指す。

## 2. ユーザーとユースケース

| 想定ユーザー | ユースケース |
| --- | --- |
| 親世代のアルバムを整理したい子世代 | 実家のアルバムを訪問中に一気に取り込む |
| 写真整理が趣味のユーザー | 自分の古いアルバムを iCloud 写真に統合する |
| ファミリー向け用途 | 家族で共有するアルバム作成の前処理 |

**メインシナリオ (Happy Path)**
1. アプリを起動し「アルバムを撮影」をタップ
2. 端末カメラでアルバム 1 ページを撮影（ドキュメントスキャナ UI を利用）
3. ページ内の写真領域が自動検出され、矩形でオーバーレイ表示される
4. 必要に応じて矩形を手動で調整／追加／削除
5. 「書き出し」で写真ライブラリ or アプリ内ライブラリへ保存

## 3. 機能要件

### 3.1 必須機能 (MVP)
- [x] ページ画像の取得
  - カメラ撮影（`VisionKit.VNDocumentCameraViewController` によるエッジ検出撮影）
  - フォトライブラリからの読み込み（`PhotosUI.PhotosPicker`）
- [x] ページ内の写真領域の自動検出
  - `Vision.VNDetectRectanglesRequest` による複数矩形検出
  - アスペクト比・最小/最大サイズ・信頼度でフィルタ
- [x] 検出結果のプレビューと手動編集
  - 矩形のドラッグ／リサイズ
  - 矩形の追加／削除
- [x] パースペクティブ補正 & クロップ
  - `CoreImage.CIPerspectiveCorrection` で 4 点補正
- [x] 書き出し
  - 写真ライブラリへ保存（`PhotoKit`）
  - ページ単位でまとめて保存

### 3.2 将来機能 (Nice to have)
- [ ] 反射・グレアの低減（CoreImage フィルタ or CoreML）
- [ ] 色補正・退色復元（`CIColorControls` / `CIVibrance`）
- [ ] ページ内のメモ（日付・場所）OCR（`VNRecognizeTextRequest`）
- [ ] Live Text による手書きキャプション抽出
- [ ] iCloud 同期 / 家族共有アルバム連携
- [ ] 複数ページの一括処理キュー
- [ ] iPad 対応 / Split View

## 4. 非機能要件
- **iOS バージョン**: iOS 17.0+（`PhotosPicker` / 最新 Vision API を前提）
- **デバイス**: iPhone 縦向き優先、iPad 対応は将来
- **オフライン動作**: 全ての画像処理は端末内で完結（ネットワーク通信なし）
- **プライバシー**: 撮影した画像や検出結果をサーバーに送らない。解析結果はユーザーが保存しない限り破棄。

## 5. 技術スタック

| 層 | 採用技術 | 理由 |
| --- | --- | --- |
| UI | SwiftUI | 最新のリアクティブ UI。iOS 17 ターゲットなら十分安定。|
| 撮影 | VisionKit (`VNDocumentCameraViewController`) | 台紙のエッジ検出・遠近補正が無料で得られる |
| 検出 | Vision (`VNDetectRectanglesRequest`) | オンデバイスで高速、複数矩形対応 |
| 画像処理 | Core Image (`CIPerspectiveCorrection`, `CIColorControls`) | Metal 最適化で高速 |
| 永続化 | PhotoKit | 写真ライブラリへ書き出し |
| 状態管理 | `@Observable` (iOS 17) | Swift Concurrency と相性良し |
| プロジェクト生成 | [XcodeGen](https://github.com/yonaskolb/XcodeGen) | `project.yml` で管理し、差分レビューしやすく |

## 6. 画面構成

```
┌─────────────────────┐
│  Home               │  ← エントリ画面
│  ┌───────────────┐  │
│  │ + アルバムを撮影 │  │  → Scanner
│  └───────────────┘  │
│  ┌───────────────┐  │
│  │ 写真を選択      │  │  → PhotosPicker
│  └───────────────┘  │
│  最近処理したページ   │
│  ・...              │
└─────────────────────┘
        │
        ▼
┌─────────────────────┐
│  Scanner (撮影)      │   VisionKit のネイティブ UI
└─────────────────────┘
        │
        ▼
┌─────────────────────┐
│  DetectionResult    │
│  ┌───────────────┐  │
│  │ ページ画像       │  │
│  │  ┏━┓ ┏━┓      │  │  ← 検出された矩形
│  │  ┗━┛ ┗━┛      │  │
│  │  ┏━━━━┓       │  │
│  │  ┗━━━━┛       │  │
│  └───────────────┘  │
│  [追加] [削除] [保存] │
└─────────────────────┘
        │
        ▼
┌─────────────────────┐
│  PhotoPreview       │  個別の写真プレビュー / 写真ライブラリへ書き出し
└─────────────────────┘
```

## 7. データモデル

```swift
/// 1 枚のアルバムページ
struct AlbumPage: Identifiable {
    let id: UUID
    var sourceImage: UIImage       // 撮影した原本
    var detections: [DetectedPhoto] // 検出された写真の矩形
}

/// ページ内で検出された 1 枚の写真
struct DetectedPhoto: Identifiable {
    let id: UUID
    var quad: Quadrilateral        // 4 点の座標（画像空間、0...1 正規化）
    var croppedImage: UIImage?     // クロップ後画像（遅延生成）
    var confidence: Float
}

struct Quadrilateral {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomLeft: CGPoint
    var bottomRight: CGPoint
}
```

## 8. 写真検出ロジック

1. ページ画像を Vision の `VNImageRequestHandler` に渡す。
2. `VNDetectRectanglesRequest` に以下のパラメータ:
   - `minimumAspectRatio = 0.3`
   - `maximumAspectRatio = 1.0 / 0.3`
   - `minimumSize = 0.1`（ページ全体の 10% 以上）
   - `maximumObservations = 16`（アルバム 1 ページは大抵 2〜8 枚）
   - `minimumConfidence = 0.6`
3. 重なり合う矩形を IoU で統合（重複除去）。
4. 面積でソート → 上位 N 件を採用。
5. 残った矩形をユーザー編集 UI に渡す。

## 9. クロップロジック

```swift
func crop(image: CIImage, quad: Quadrilateral) -> CIImage {
    let filter = CIFilter.perspectiveCorrection()
    filter.inputImage = image
    filter.topLeft     = quad.topLeft.applying(imageTransform)
    filter.topRight    = quad.topRight.applying(imageTransform)
    filter.bottomLeft  = quad.bottomLeft.applying(imageTransform)
    filter.bottomRight = quad.bottomRight.applying(imageTransform)
    return filter.outputImage!
}
```

- Vision の座標系（左下原点・正規化）と UIKit 座標系（左上原点・pt）の変換をユーティリティに閉じ込める。

## 10. パーミッション

| Info.plist キー | 用途 |
| --- | --- |
| `NSCameraUsageDescription` | アルバムページを撮影する |
| `NSPhotoLibraryUsageDescription` | ライブラリから既存の写真を読み込む |
| `NSPhotoLibraryAddUsageDescription` | 切り出した写真をライブラリに保存する |

## 11. ファイル構成

```
Album-to-Photo/
├── README.md
├── project.yml                         # XcodeGen 設定
├── docs/
│   └── design.md                       # 本ドキュメント
├── AlbumToPhoto/
│   ├── App/
│   │   └── AlbumToPhotoApp.swift
│   ├── Features/
│   │   ├── Home/
│   │   │   └── HomeView.swift
│   │   ├── Scanner/
│   │   │   └── DocumentScannerView.swift
│   │   └── Detection/
│   │       ├── DetectionResultView.swift
│   │       ├── DetectionResultViewModel.swift
│   │       └── QuadrilateralEditor.swift
│   ├── Services/
│   │   ├── PhotoDetector.swift
│   │   ├── PhotoCropper.swift
│   │   └── PhotoLibraryService.swift
│   ├── Models/
│   │   ├── AlbumPage.swift
│   │   ├── DetectedPhoto.swift
│   │   └── Quadrilateral.swift
│   ├── Utilities/
│   │   ├── CGGeometry+Extensions.swift
│   │   └── UIImage+Orientation.swift
│   └── Resources/
│       ├── Assets.xcassets/
│       └── Info.plist
├── AlbumToPhotoTests/
│   └── PhotoDetectorTests.swift
└── .gitignore
```

## 12. 開発ロードマップ

| フェーズ | 内容 | 完了条件 |
| --- | --- | --- |
| P0 | 本リポジトリの初期化 + 企画設計 (本ドキュメント) | PR マージ |
| P1 (MVP) | XcodeGen スキャフォールド、撮影 + 自動検出 + 書き出しの最短経路 | 1 ページから複数写真を切り出して保存できる |
| P2 | 手動編集 UI（矩形ドラッグ）、品質向上（回転/補正） | 検出精度が低いページも手動で整えて保存できる |
| P3 | ページ履歴・一括処理・iPad 対応 | 本格運用 |

## 13. 本リポジトリでの今回の成果物

- 本設計ドキュメント (`docs/design.md`)
- `README.md`（セットアップ手順・ビルド方法）
- XcodeGen 用 `project.yml`
- P1 相当の Swift / SwiftUI ソースコード一式
- 最低限の単体テスト

> ⚠️ Devin の作業環境は Linux のため、Xcode での実ビルド / 実機動作確認は行っていません。
> kuma-relax さん側の Mac で `xcodegen generate` → Xcode で開いて動作確認をお願いします。
