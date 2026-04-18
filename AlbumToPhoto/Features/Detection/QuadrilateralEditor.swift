import SwiftUI

/// ページ画像の上に 4 点の矩形を描画し、ドラッグで調整できるオーバーレイ。
struct QuadrilateralEditor: View {

    /// 画像ピクセル座標系の Quadrilateral。
    @Binding var quad: Quadrilateral

    /// 画像ピクセル → View 座標の変換に用いる倍率。
    /// 例: 画像が 4000x3000 で View が 400x300 なら 0.1。
    let scale: CGFloat

    /// 表示色。
    let tint: Color

    /// 選択中かどうか（強調表示用）。
    let isSelected: Bool

    /// ドラッグ中の頂点。
    @State private var draggingCorner: Corner?

    enum Corner { case topLeft, topRight, bottomRight, bottomLeft }

    var body: some View {
        ZStack {
            edgesShape
                .stroke(tint, lineWidth: isSelected ? 3 : 2)
                .background(
                    edgesShape.fill(tint.opacity(isSelected ? 0.18 : 0.08))
                )

            cornerHandle(.topLeft, point: quad.topLeft)
            cornerHandle(.topRight, point: quad.topRight)
            cornerHandle(.bottomRight, point: quad.bottomRight)
            cornerHandle(.bottomLeft, point: quad.bottomLeft)
        }
        .allowsHitTesting(isSelected)
    }

    // MARK: - Shape

    private var edgesShape: some Shape {
        QuadShape(
            topLeft: quad.topLeft * scale,
            topRight: quad.topRight * scale,
            bottomRight: quad.bottomRight * scale,
            bottomLeft: quad.bottomLeft * scale
        )
    }

    // MARK: - Corner handle

    private func cornerHandle(_ corner: Corner, point: CGPoint) -> some View {
        let viewPoint = point * scale
        return Circle()
            .fill(Color.white)
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(tint, lineWidth: 3))
            .position(viewPoint)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        draggingCorner = corner
                        let newImagePoint = CGPoint(
                            x: value.location.x / scale,
                            y: value.location.y / scale
                        )
                        setCorner(corner, to: newImagePoint)
                    }
                    .onEnded { _ in draggingCorner = nil }
            )
    }

    private func setCorner(_ corner: Corner, to point: CGPoint) {
        switch corner {
        case .topLeft: quad.topLeft = point
        case .topRight: quad.topRight = point
        case .bottomRight: quad.bottomRight = point
        case .bottomLeft: quad.bottomLeft = point
        }
    }
}

/// 4 点の Quadrilateral を描画する SwiftUI Shape。
private struct QuadShape: Shape {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: topLeft)
        path.addLine(to: topRight)
        path.addLine(to: bottomRight)
        path.addLine(to: bottomLeft)
        path.closeSubpath()
        return path
    }
}
