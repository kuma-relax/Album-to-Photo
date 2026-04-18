import SwiftUI

/// 検出結果のプレビュー + 矩形編集 + 書き出し画面。
struct DetectionResultView: View {

    @State private var viewModel: DetectionResultViewModel
    @State private var selectedDetectionID: UUID?
    @State private var showSavedToast = false

    init(page: AlbumPage) {
        _viewModel = State(initialValue: DetectionResultViewModel(page: page))
    }

    var body: some View {
        VStack(spacing: 0) {
            canvas
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))

            Divider()

            detectionList
        }
        .navigationTitle("検出結果")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        viewModel.addDetectionAtCenter()
                    } label: {
                        Label("矩形を追加", systemImage: "plus.square.dashed")
                    }
                    Button(role: .destructive) {
                        if let id = selectedDetectionID {
                            viewModel.removeDetection(id: id)
                            selectedDetectionID = nil
                        }
                    } label: {
                        Label("選択中の矩形を削除", systemImage: "trash")
                    }
                    .disabled(selectedDetectionID == nil)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .task {
            await viewModel.runDetectionIfNeeded()
        }
        .overlay {
            switch viewModel.phase {
            case .detecting:
                ProgressOverlay(text: "写真を検出しています…")
            case .saving:
                ProgressOverlay(text: "写真ライブラリに保存中…")
            default:
                EmptyView()
            }
        }
        .overlay(alignment: .top) {
            if showSavedToast {
                Text("写真ライブラリに保存しました")
                    .font(.footnote)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .alert(
            "エラー",
            isPresented: Binding(
                get: {
                    if case .failed = viewModel.phase { return true } else { return false }
                },
                set: { _ in }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if case .failed(let message) = viewModel.phase {
                Text(message)
            }
        }
        .onChange(of: viewModel.saveCompletedToastID) { _, newValue in
            guard newValue != nil else { return }
            withAnimation { showSavedToast = true }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    withAnimation { showSavedToast = false }
                }
            }
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { proxy in
            let imageSize = viewModel.page.sourceImage.size
            let scale = min(
                proxy.size.width / imageSize.width,
                proxy.size.height / imageSize.height
            )
            let displayWidth = imageSize.width * scale
            let displayHeight = imageSize.height * scale
            let origin = CGPoint(
                x: (proxy.size.width - displayWidth) / 2,
                y: (proxy.size.height - displayHeight) / 2
            )

            ZStack(alignment: .topLeading) {
                Image(uiImage: viewModel.page.sourceImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: displayWidth, height: displayHeight)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                ForEach(viewModel.page.detections) { detection in
                    QuadrilateralEditor(
                        quad: binding(for: detection.id),
                        scale: scale,
                        tint: detection.isExported ? .green : .accentColor,
                        isSelected: selectedDetectionID == detection.id
                    )
                    .frame(width: displayWidth, height: displayHeight)
                    .position(
                        x: origin.x + displayWidth / 2,
                        y: origin.y + displayHeight / 2
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedDetectionID = detection.id
                    }
                }
            }
        }
        .frame(minHeight: 320)
    }

    // MARK: - List

    private var detectionList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if viewModel.page.detections.isEmpty, case .ready = viewModel.phase {
                    Text("検出された写真はありません。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                }

                ForEach(viewModel.page.detections) { detection in
                    detectionThumbnail(detection)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(height: 120)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func detectionThumbnail(_ detection: DetectedPhoto) -> some View {
        let isSelected = selectedDetectionID == detection.id
        return Button {
            selectedDetectionID = detection.id
            viewModel.ensureCroppedImage(for: detection.id)
        } label: {
            ZStack {
                if let image = detection.croppedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            viewModel.ensureCroppedImage(for: detection.id)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.page.detections.count) 枚検出")
                    .font(.footnote).bold()
                if case .ready = viewModel.phase {
                    Text("タップして矩形を微調整できます")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await viewModel.saveAllToPhotoLibrary() }
            } label: {
                Label("写真ライブラリに保存", systemImage: "square.and.arrow.down")
                    .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.page.detections.isEmpty || viewModel.phase == .detecting || viewModel.phase == .saving)
        }
        .padding()
        .background(.thinMaterial)
    }

    // MARK: - Bindings

    private func binding(for id: UUID) -> Binding<Quadrilateral> {
        Binding(
            get: {
                viewModel.page.detections.first(where: { $0.id == id })?.quad
                    ?? Quadrilateral(rect: .zero)
            },
            set: { newValue in
                viewModel.updateQuad(for: id, to: newValue)
            }
        )
    }
}

// MARK: - ProgressOverlay

private struct ProgressOverlay: View {
    let text: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text(text).font(.callout)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
