import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

enum AppIconRenderer {
    static func write(to path: String) throws {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw DisplayFailure(message: "无法创建应用图标。")
        }
        func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
            CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        }
        func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
            CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        func gradient(_ path: CGPath, colors: [CGColor], from start: CGPoint, to end: CGPoint) {
            guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil) else { return }
            context.saveGState()
            context.addPath(path)
            context.clip()
            context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            context.restoreGState()
        }
        func glow(_ center: CGPoint, radius: CGFloat, color: CGColor) {
            guard let transparent = color.copy(alpha: 0),
                  let gradient = CGGradient(colorsSpace: space, colors: [color, transparent] as CFArray, locations: [0, 1]) else { return }
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: radius, options: [])
        }

        // Leave the standard optical margin around a single, uncluttered silhouette.
        // Details are deliberately broad enough to survive the 16-pixel ICNS size.
        let tile = roundedPath(CGRect(x: 56, y: 56, width: 912, height: 912), radius: 204)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0.02, 0.07, 0.21, 0.24))
        context.setFillColor(color(0.10, 0.23, 0.58))
        context.addPath(tile)
        context.fillPath()
        context.restoreGState()
        gradient(tile, colors: [color(0.10, 0.18, 0.47), color(0.15, 0.37, 0.86), color(0.23, 0.59, 0.96)],
                 from: CGPoint(x: 760, y: 80), to: CGPoint(x: 280, y: 968))
        context.saveGState()
        context.addPath(tile)
        context.clip()
        glow(CGPoint(x: 100, y: 920), radius: 720, color: color(0.48, 0.92, 1, 0.40))
        glow(CGPoint(x: 1000, y: 120), radius: 700, color: color(0.34, 0.21, 0.93, 0.32))
        context.setStrokeColor(color(0.78, 0.92, 1, 0.24))
        context.setLineWidth(3)
        context.addPath(roundedPath(CGRect(x: 58, y: 58, width: 908, height: 908), radius: 202))
        context.strokePath()
        context.restoreGState()

        let stem = roundedPath(CGRect(x: 476, y: 252, width: 72, height: 124), radius: 12)
        let foot = roundedPath(CGRect(x: 366, y: 230, width: 292, height: 38), radius: 19)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -15), blur: 24, color: color(0.01, 0.04, 0.20, 0.30))
        context.setFillColor(color(0.77, 0.86, 0.98))
        context.addPath(stem)
        context.addPath(foot)
        context.fillPath()
        context.restoreGState()
        gradient(stem, colors: [color(0.88, 0.94, 1), color(0.60, 0.74, 0.93)],
                 from: CGPoint(x: 512, y: 264), to: CGPoint(x: 512, y: 366))
        gradient(foot, colors: [color(0.75, 0.86, 0.98), color(0.97, 0.99, 1)],
                 from: CGPoint(x: 512, y: 230), to: CGPoint(x: 512, y: 268))

        let monitor = roundedPath(CGRect(x: 174, y: 344, width: 676, height: 440), radius: 48)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -16), blur: 35, color: color(0.01, 0.04, 0.18, 0.35))
        context.setFillColor(color(0.92, 0.97, 1))
        context.addPath(monitor)
        context.fillPath()
        context.restoreGState()
        gradient(monitor, colors: [color(0.77, 0.88, 0.99), color(0.98, 1, 1)],
                 from: CGPoint(x: 512, y: 344), to: CGPoint(x: 512, y: 784))

        let screen = roundedPath(CGRect(x: 194, y: 391, width: 636, height: 373), radius: 29)
        gradient(screen, colors: [color(0.15, 0.12, 0.51), color(0.10, 0.34, 0.83), color(0.12, 0.76, 0.91)],
                 from: CGPoint(x: 780, y: 420), to: CGPoint(x: 240, y: 760))
        context.saveGState()
        context.addPath(screen)
        context.clip()
        glow(CGPoint(x: 244, y: 738), radius: 390, color: color(0.39, 1, 0.96, 0.65))
        glow(CGPoint(x: 760, y: 400), radius: 360, color: color(0.39, 0.25, 1, 0.48))
        context.restoreGState()

        // The diagonal expansion mark suggests display scaling without lettering.
        let scale = CGMutablePath()
        scale.move(to: CGPoint(x: 429, y: 494))
        scale.addLine(to: CGPoint(x: 595, y: 660))
        scale.move(to: CGPoint(x: 429, y: 558))
        scale.addLine(to: CGPoint(x: 429, y: 494))
        scale.addLine(to: CGPoint(x: 493, y: 494))
        scale.move(to: CGPoint(x: 531, y: 660))
        scale.addLine(to: CGPoint(x: 595, y: 660))
        scale.addLine(to: CGPoint(x: 595, y: 596))
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: color(0.02, 0.15, 0.40, 0.24))
        context.setStrokeColor(color(0.94, 1, 1, 0.96))
        context.setLineWidth(18)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(scale)
        context.strokePath()
        context.restoreGState()
        guard let bitmap = context.makeImage() else { throw DisplayFailure(message: "无法渲染图标。") }
        if URL(fileURLWithPath: path).pathExtension == "icns" {
            try writeICNS(bitmap, space: space, path: path)
            return
        }
        guard let output = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                          UTType.png.identifier as CFString, 1, nil) else {
            throw DisplayFailure(message: "无法写入应用图标。")
        }
        CGImageDestinationAddImage(output, bitmap, nil)
        guard CGImageDestinationFinalize(output) else { throw DisplayFailure(message: "保存应用图标失败。") }
    }

    private static func writeICNS(_ image: CGImage, space: CGColorSpace, path: String) throws {
        func length(_ value: Int) -> Data {
            var big = UInt32(value).bigEndian
            return withUnsafeBytes(of: &big) { Data($0) }
        }
        var chunks = Data()
        for (size, type) in [(16, "icp4"), (32, "icp5"), (64, "icp6"), (128, "ic07"),
                             (256, "ic08"), (512, "ic09"), (1024, "ic10")] {
            guard let canvas = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                         bytesPerRow: 0, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw DisplayFailure(message: "无法缩放应用图标。")
            }
            canvas.interpolationQuality = .high
            canvas.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            let data = NSMutableData()
            guard let scaled = canvas.makeImage(),
                  let encoder = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
                throw DisplayFailure(message: "无法编码应用图标。")
            }
            CGImageDestinationAddImage(encoder, scaled, nil)
            guard CGImageDestinationFinalize(encoder) else { throw DisplayFailure(message: "无法编码应用图标。") }
            chunks.append(Data(type.utf8))
            chunks.append(length(data.length + 8))
            chunks.append(data as Data)
        }
        var result = Data("icns".utf8)
        result.append(length(chunks.count + 8))
        result.append(chunks)
        try result.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
