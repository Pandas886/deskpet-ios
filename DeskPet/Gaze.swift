import Foundation
import CoreGraphics

enum Gaze {
    // Input is an upright, mirrored camera frame. Vision's origin is bottom-left.
    static func target(for face: CGRect) -> CGPoint {
        CGPoint(x: min(1, max(-1, (face.midX - 0.5) * 2)),
                y: min(1, max(-1, (0.5 - face.midY) * 2)))
    }

    static func previewRect(for face: CGRect, imageSize: CGSize, bounds: CGRect) -> CGRect {
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(x: bounds.midX - width / 2 + face.minX * width,
                      y: bounds.midY - height / 2 + (1 - face.maxY) * height,
                      width: face.width * width, height: face.height * height)
    }
}
