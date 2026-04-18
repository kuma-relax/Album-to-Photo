import PhotosUI
import SwiftUI

/// アプリのエントリ画面。
/// - 「アルバムを撮影」→ ドキュメントスキャナを起動
/// - 「写真を選択」→ フォトライブラリから既存画像を読み込み
struct HomeView: View {

    @State private var isShowingScanner = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var pendingPage: AlbumPage?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    VStack(spacing: 12) {
                        Button {
                            isShowingScanner = true
                        } label: {
                            ActionTile(
                                systemImage: "camera.viewfinder",
                                title: "アルバムを撮影",
                                subtitle: "カメラでアルバムの1ページを撮影します"
                            )
                        }
                        .buttonStyle(.plain)

                        PhotosPicker(
                            selection: $selectedItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            ActionTile(
                                systemImage: "photo.on.rectangle.angled",
                                title: "写真を選択",
                                subtitle: "既存のページ画像から切り出します"
                            )
                        }
                    }

                    usageGuide
                }
                .padding()
            }
            .navigationTitle("Album to Photo")
            .sheet(isPresented: $isShowingScanner) {
                DocumentScannerView { result in
                    isShowingScanner = false
                    handleScannerResult(result)
                }
                .ignoresSafeArea()
            }
            .navigationDestination(item: $pendingPage) { page in
                DetectionResultView(page: page)
            }
            .onChange(of: selectedItem) { _, newValue in
                guard let newValue else { return }
                Task { await loadPickedItem(newValue) }
            }
            .alert("エラー", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("昔のアルバムを、サクッとデジタル化。")
                .font(.title2)
                .bold()
            Text("透明フィルム式アルバムの1ページを撮影するだけで、貼り付けられた写真を自動で切り出します。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var usageGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("ページ全体が収まるように真上から撮影してください", systemImage: "1.circle.fill")
            Label("光の反射が少ない環境だと検出精度が上がります", systemImage: "2.circle.fill")
            Label("検出結果は撮影後に手動で微調整できます", systemImage: "3.circle.fill")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    // MARK: - Handlers

    private func handleScannerResult(_ result: Result<[UIImage], Error>) {
        switch result {
        case .success(let images):
            guard let firstImage = images.first else { return }
            pendingPage = AlbumPage(sourceImage: firstImage.normalizedOrientation())
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func loadPickedItem(_ item: PhotosPickerItem) async {
        defer { selectedItem = nil }
        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                errorMessage = "画像を読み込めませんでした。"
                return
            }
            await MainActor.run {
                pendingPage = AlbumPage(sourceImage: image.normalizedOrientation())
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Subviews

private struct ActionTile: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.tint)
                .frame(width: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

// MARK: - AlbumPage Hashable for navigationDestination

extension AlbumPage: Hashable {
    static func == (lhs: AlbumPage, rhs: AlbumPage) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

#Preview {
    HomeView()
}
