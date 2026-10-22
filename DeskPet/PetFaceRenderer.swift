import UIKit

struct PetFacePose {
    var opening: CGFloat = 1
    var smile: CGFloat = 0
    var asymmetry: CGFloat = 0
    var pupil: CGFloat = 1
    var lean: CGFloat = 0
    var warmth: CGFloat = 0

    static func target(_ mood: PetMood) -> PetFacePose {
        switch mood {
        case .happy: return PetFacePose(opening: 0.8, smile: 0.88, lean: -0.035, warmth: 0.65)
        case .relaxed: return PetFacePose(opening: 0.66, smile: 1, lean: 0.065, warmth: 1)
        case .sleepy: return PetFacePose(opening: 0.18, pupil: 1.05, lean: 0.025)
        case .curious: return PetFacePose(asymmetry: 0.12, pupil: 1.03, lean: 0.07)
        case .startled: return PetFacePose(opening: 1.1, pupil: 0.73, lean: -0.035)
        case .held: return PetFacePose(opening: 1.06, asymmetry: 0.06, pupil: 0.82)
        case .shy: return PetFacePose(opening: 0.65, asymmetry: -0.08, lean: -0.10, warmth: 0.35)
        case .settling: return PetFacePose(opening: 0.85, smile: 0.35, warmth: 0.25)
        case .calm: return PetFacePose()
        }
    }

    mutating func approach(_ other: PetFacePose, amount: CGFloat) {
        opening += (other.opening - opening) * amount
        smile += (other.smile - smile) * amount
        asymmetry += (other.asymmetry - asymmetry) * amount
        pupil += (other.pupil - pupil) * amount
        lean += (other.lean - lean) * amount
        warmth += (other.warmth - warmth) * amount
    }
}

final class PetFaceRenderer {
    private let colors = CGColorSpaceCreateDeviceRGB()
    private lazy var bodyTexture = makeBodyTexture()
    private lazy var coreTexture = makeCoreTexture()

    // Render light and material once; gaze and expression only transform the cached layers.
    private func makeBodyTexture() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: 312, height: 288), format: format).image { output in
            let context = output.cgContext
            let body = CGRect(x: 44, y: 44, width: 224, height: 200)
            let outline = UIBezierPath(roundedRect: body, cornerRadius: 70)
            context.setShadow(offset: .zero, blur: 26, color: UIColor(red: 1, green: 0.37, blue: 0.035, alpha: 0.7).cgColor)
            UIColor(red: 0.95, green: 0.55, blue: 0.12, alpha: 1).setFill()
            outline.fill()
            context.setShadow(offset: .zero, blur: 0, color: nil)
            context.saveGState()
            outline.addClip()
            let rim = CGGradient(colorsSpace: colors,
                                 colors: [UIColor(red: 0.43, green: 0.18, blue: 0.025, alpha: 1).cgColor,
                                          UIColor(red: 1, green: 0.83, blue: 0.37, alpha: 1).cgColor,
                                          UIColor(red: 0.87, green: 0.40, blue: 0.065, alpha: 1).cgColor] as CFArray,
                                 locations: [0, 0.5, 1])!
            context.drawLinearGradient(rim, start: CGPoint(x: body.midX, y: body.minY), end: CGPoint(x: body.midX, y: body.maxY), options: [])
            UIBezierPath(roundedRect: body.insetBy(dx: 8, dy: 8), cornerRadius: 62).addClip()
            let inner = CGGradient(colorsSpace: colors,
                                   colors: [UIColor(red: 1, green: 0.95, blue: 0.67, alpha: 1).cgColor,
                                            UIColor(red: 1, green: 0.78, blue: 0.22, alpha: 1).cgColor,
                                            UIColor(red: 0.92, green: 0.47, blue: 0.06, alpha: 1).cgColor] as CFArray,
                                   locations: [0, 0.72, 1])!
            let center = CGPoint(x: body.midX, y: body.midY + 6)
            context.drawRadialGradient(inner, startCenter: center, startRadius: 0, endCenter: center,
                                       endRadius: 145, options: .drawsAfterEndLocation)
            context.restoreGState()
            UIColor(red: 1, green: 0.94, blue: 0.65, alpha: 0.85).setStroke()
            outline.lineWidth = 1.6
            outline.stroke()
            context.setShadow(offset: .zero, blur: 3, color: UIColor.white.cgColor)
            UIColor(white: 1, alpha: 0.85).setFill()
            UIBezierPath(ovalIn: CGRect(x: 122, y: 62, width: 27, height: 13)).fill()
        }
    }

    private func makeCoreTexture() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: 140, height: 170), format: format).image { output in
            output.cgContext.setShadow(offset: .zero, blur: 18,
                                       color: UIColor(red: 1, green: 0.97, blue: 0.65, alpha: 1).cgColor)
            UIColor(red: 1, green: 0.985, blue: 0.91, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 24, y: 24, width: 92, height: 122), cornerRadius: 42).fill()
        }
    }

    // A fast close and softer reopening, independent of display refresh rate.
    static func blinkClosure(elapsed: TimeInterval) -> CGFloat {
        if elapsed < 0 || elapsed >= 0.24 { return 0 }
        if elapsed < 0.075 { return CGFloat(sin(elapsed / 0.075 * .pi / 2)) }
        let t = (elapsed - 0.075) / 0.165
        return CGFloat(1 - t * t * (3 - 2 * t))
    }

    func draw(in context: CGContext, bounds: CGRect, gaze: CGPoint, pose: PetFacePose,
              closure: CGFloat, now: TimeInterval) {
        let width = min(bounds.width * 0.225, bounds.height * 0.50)
        let height = width * 0.90
        let gap = width * 0.43
        let center = CGPoint(x: bounds.midX + gaze.x * 15,
                             y: bounds.midY - 10 + gaze.y * 8 + sin(now * 1.3) * 0.8)
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: pose.lean)
        context.translateBy(x: -center.x, y: -center.y)
        for side: CGFloat in [-1, 1] {
            let scale = 1 + side * pose.asymmetry
            let eye = CGRect(x: center.x + side * (width + gap) / 2 - width / 2,
                             y: center.y - height * scale / 2 - side * pose.asymmetry * 12,
                             width: width, height: height * scale)
            drawEye(in: context, frame: eye, gaze: gaze, pose: pose, closure: closure)
        }
        context.restoreGState()
    }

    private func drawEye(in context: CGContext, frame: CGRect, gaze: CGPoint,
                         pose: PetFacePose, closure: CGFloat) {
        let shut = max(closure, pose.smile * 0.96)
        let opening = max(0.015, pose.opening * (1 - shut))
        let height = frame.height * min(1.12, opening)
        let body = CGRect(x: frame.minX, y: frame.midY - height / 2,
                          width: frame.width, height: height)
        let fade = max(0, min(1, (0.84 - shut) / 0.30))
        context.saveGState()
        context.setAlpha(fade)
        bodyTexture.draw(in: CGRect(x: body.minX - body.width * 44 / 224,
                                    y: body.minY - body.height * 44 / 200,
                                    width: body.width * 312 / 224, height: body.height * 288 / 200))
        let aperture = UIBezierPath(roundedRect: body.insetBy(dx: 5, dy: min(5, height * 0.1)),
                                    cornerRadius: min(body.width * 0.28, body.height * 0.36))
        aperture.addClip()
        let core = CGRect(x: body.midX + gaze.x * frame.width * 0.13 - frame.width * 0.21 * pose.pupil,
                          y: body.midY + gaze.y * frame.height * 0.10 - frame.height * 0.285 * pose.pupil,
                          width: frame.width * 0.42 * pose.pupil, height: frame.height * 0.57 * pose.pupil)
        coreTexture.draw(in: CGRect(x: core.minX - core.width * 24 / 92, y: core.minY - core.height * 24 / 122,
                                    width: core.width * 140 / 92, height: core.height * 170 / 122))
        context.restoreGState()

        if shut > 0.65 {
            let alpha = min(1, (shut - 0.65) / 0.25)
            let lid = UIBezierPath()
            let y = frame.midY + frame.height * 0.02
            let bend = frame.height * (0.025 + pose.smile * 0.20)
            lid.move(to: CGPoint(x: frame.minX + frame.width * 0.14, y: y + bend * 0.25))
            lid.addCurve(to: CGPoint(x: frame.maxX - frame.width * 0.14, y: y + bend * 0.25),
                         controlPoint1: CGPoint(x: frame.minX + frame.width * 0.32, y: y - bend),
                         controlPoint2: CGPoint(x: frame.maxX - frame.width * 0.32, y: y - bend))
            context.saveGState()
            context.setShadow(offset: .zero, blur: 14,
                              color: UIColor(red: 1, green: 0.40, blue: 0.04, alpha: alpha * 0.8).cgColor)
            UIColor(red: 1, green: 0.73, blue: 0.23, alpha: alpha).setStroke()
            lid.lineWidth = frame.width * 0.060
            lid.lineCapStyle = .round
            lid.stroke()
            UIColor(red: 1, green: 0.96, blue: 0.71, alpha: alpha * 0.9).setStroke()
            lid.lineWidth = frame.width * 0.018
            lid.stroke()
            context.restoreGState()
        }
    }

    #if DEBUG
    func exportPreview() {
        let size = CGSize(width: 896, height: 1242)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { output in
            UIColor.black.setFill()
            output.fill(CGRect(origin: .zero, size: size))
            for (index, mood) in [PetMood.calm, .curious, .relaxed].enumerated() {
                draw(in: output.cgContext, bounds: CGRect(x: 0, y: CGFloat(index) * 414, width: 896, height: 414),
                     gaze: mood == .curious ? CGPoint(x: -0.4, y: -0.15) : .zero,
                     pose: .target(mood), closure: 0, now: 0)
            }
        }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("face-preview.png")
        try? image.pngData()?.write(to: url)
        print("DeskPet face preview: style=amber-light, exported=\(FileManager.default.fileExists(atPath: url.path))")
    }
    #endif
}
