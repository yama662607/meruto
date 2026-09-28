import CoreGraphics
import MerutoCore
import SwiftUI

/// 補間したヒートマップを小さな RGBA 画像にする。表示側で拡大するとバイリニア補間で滑らかに見える。
enum HeatmapRenderer {
    static func image(for survey: Survey, bounds: SurveyBounds, columns: Int = 72, maxAlpha: Double = 0.82) -> CGImage? {
        guard !survey.points.isEmpty, bounds.width > 0, bounds.height > 0 else { return nil }
        let rows = max(1, Int((Double(columns) * bounds.height / bounds.width).rounded()))
        let map = HeatmapBuilder.build(points: survey.points, bounds: bounds, columns: columns, rows: rows)
        return image(for: map, maxAlpha: maxAlpha)
    }

    static func image(for map: Heatmap, maxAlpha: Double) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: map.columns * map.rows * 4)
        for row in 0..<map.rows {
            for column in 0..<map.columns {
                let alpha = map.opacity(column: column, row: row) * maxAlpha
                guard alpha > 0 else { continue }
                let rgb = QualityColor.rgb(for: map.value(column: column, row: row))
                let index = (row * map.columns + column) * 4
                // premultiplied
                pixels[index] = UInt8(rgb.r * alpha * 255)
                pixels[index + 1] = UInt8(rgb.g * alpha * 255)
                pixels[index + 2] = UInt8(rgb.b * alpha * 255)
                pixels[index + 3] = UInt8(alpha * 255)
            }
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: map.columns, height: map.rows, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: map.columns * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// ウィジェットや一覧のサムネイル用の静的なヒートマップ。
struct HeatmapThumbnail: View {
    let survey: Survey

    var body: some View {
        GeometryReader { geo in
            let aspect = geo.size.width / max(1, geo.size.height)
            let bounds = survey.bounds.fitted(toAspect: aspect)
            ZStack {
                if let image = HeatmapRenderer.image(for: survey, bounds: bounds, columns: 48) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .blur(radius: 1.5)
                }
                Canvas { context, size in
                    for point in survey.points {
                        let x = (point.x - bounds.minX) / bounds.width * size.width
                        let y = (bounds.maxY - point.y) / bounds.height * size.height
                        let rect = CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)
                        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.7)))
                    }
                }
            }
        }
    }
}
