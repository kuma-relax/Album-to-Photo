# Album to Photo

> 昔ながらの透明フィルム式アルバム（台紙に写真を貼り、上から透明フィルムで押さえるタイプ）の 1 ページを丸ごと撮影し、**貼り付けられている写真を 1 枚ずつ自動で切り出す** iOS アプリ。

企画・設計の詳細は [`docs/design.md`](docs/design.md) を参照してください。

## スクリーン構成

```
HomeView
  ├── [アルバムを撮影] → DocumentScannerView (VisionKit)
  └── [写真を選択]     → PhotosPicker
          │
          ▼
    DetectionResultView
      ├── ページ画像の上に検出された矩形をオーバーレイ
      ├── 矩形の追加 / 削除 / 4 点ドラッグで微調整
      └── [写真ライブラリに保存] → PHPhotoLibrary
```

## 技術スタック

| 層 | 技術 |
| --- | --- |
| UI | SwiftUI (iOS 17+), `@Observable` |
| 撮影 | VisionKit `VNDocumentCameraViewController` |
| 検出 | Vision `VNDetectRectanglesRequest` |
| 画像処理 | Core Image `CIPerspectiveCorrection` |
| 永続化 | PhotoKit `PHPhotoLibrary` |
| プロジェクト生成 | [XcodeGen](https://github.com/yonaskolb/XcodeGen) |

## 動作要件

- macOS 14 Sonoma 以上 + Xcode 15 以上
- iOS 17.0 以上の iPhone 実機 or シミュレータ
- `VNDocumentCameraViewController` は **シミュレータでは利用不可** のため、撮影機能の確認は実機推奨
  - シミュレータで試したい場合は「写真を選択」経由で既存画像を読み込んでください

## セットアップ

### 1. 依存ツールのインストール

XcodeGen を Homebrew でインストールします。

```bash
brew install xcodegen
```

### 2. Xcode プロジェクトを生成

```bash
git clone https://github.com/kuma-relax/Album-to-Photo.git
cd Album-to-Photo
xcodegen generate
open AlbumToPhoto.xcodeproj
```

生成された `AlbumToPhoto.xcodeproj` は `.gitignore` 済みです（`project.yml` から再生成できるためコミットしません）。

### 3. コードサイニング

初回ビルド時は Xcode 上で以下を設定してください。

1. `AlbumToPhoto` ターゲット → `Signing & Capabilities`
2. `Team` にご自身の Apple Developer アカウント (または Personal Team) を選択

`project.yml` の `DEVELOPMENT_TEAM` は空にしてあるので、好きな Team を選択してください。

### 4. 実行

- シミュレータ: iPhone 15 等を選んで `⌘R`
- 実機: デバイスを接続、証明書設定後に `⌘R`

## ビルド / テスト（CLI）

```bash
# プロジェクト生成
xcodegen generate

# ビルド
xcodebuild \
  -project AlbumToPhoto.xcodeproj \
  -scheme AlbumToPhoto \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build

# ユニットテスト
xcodebuild \
  -project AlbumToPhoto.xcodeproj \
  -scheme AlbumToPhoto \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test
```

## ディレクトリ構成

```
Album-to-Photo/
├── README.md
├── project.yml                         # XcodeGen 設定
├── docs/
│   └── design.md                       # 企画・設計ドキュメント
├── AlbumToPhoto/
│   ├── App/
│   │   └── AlbumToPhotoApp.swift       # @main エントリ
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
│   │   ├── PhotoDetector.swift         # Vision による矩形検出
│   │   ├── PhotoCropper.swift          # Core Image による遠近補正クロップ
│   │   └── PhotoLibraryService.swift   # PhotoKit 経由で保存
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
└── AlbumToPhotoTests/
    ├── PhotoDetectorTests.swift
    └── QuadrilateralTests.swift
```

## 使い方（ユーザー視点）

1. アプリを起動し **「アルバムを撮影」** をタップ。
2. iOS 標準のドキュメントスキャナが起動するので、アルバムのページを真上から撮影。
   - 自動でエッジ検出 → 遠近補正が行われます。
3. 撮影後、ページ画像の上に **検出された写真の矩形** がオーバーレイ表示されます。
4. 必要に応じて:
   - 矩形の四隅をドラッグして微調整
   - `…` メニューから「矩形を追加」「選択中の矩形を削除」
5. **「写真ライブラリに保存」** をタップすると、各矩形が個別の写真として iOS 写真ライブラリに保存されます。

## 開発ロードマップ

| フェーズ | 内容 | 状態 |
| --- | --- | --- |
| P0 | 本リポジトリの初期化 + 企画設計 | ✅ |
| P1 (MVP) | 撮影 + 自動検出 + 書き出しの最短経路 | ✅（本 PR） |
| P2 | 反射/グレア低減、色補正、OCR による日付抽出 | 未着手 |
| P3 | ページ履歴・一括処理・iPad 対応 | 未着手 |

## ライセンス

TBD（ユーザー決定）
