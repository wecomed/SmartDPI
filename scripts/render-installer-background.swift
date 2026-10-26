import AppKit

// Finder uses this image at its original size, so keep a 1x canvas.
let size = NSSize(width: 680, height: 510)
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: render-installer-background output.png\n", stderr)
    exit(2)
}

let canvas = NSImage(size: size)
canvas.lockFocus()
NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

let glow = NSGradient(colors: [
    NSColor(calibratedRed: 0.88, green: 0.94, blue: 1, alpha: 1),
    NSColor(calibratedWhite: 0.97, alpha: 1)
])!
glow.draw(in: NSRect(x: 0, y: 245, width: 680, height: 265), angle: -90)

func text(_ string: String, top: CGFloat, height: CGFloat, font: NSFont,
          color: NSColor = .labelColor, width: CGFloat = 620) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: color, .paragraphStyle: style
    ]
    string.draw(in: NSRect(x: (size.width - width) / 2,
                          y: size.height - top - height,
                          width: width, height: height), withAttributes: attributes)
}

text("拖入「应用程序」，完成安装", top: 28, height: 42,
     font: .systemFont(ofSize: 29, weight: .semibold),
     color: NSColor(calibratedWhite: 0.16, alpha: 1))
text("让尚未适配 HiDPI 的显示器，也能舒适地显示 macOS", top: 76, height: 30,
     font: .systemFont(ofSize: 15), color: NSColor(calibratedWhite: 0.4, alpha: 1))

// Leave both icon areas empty: Finder draws the actual app and folder icons.
let arrow = NSBezierPath()
arrow.lineWidth = 5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 292, y: 330))
arrow.line(to: NSPoint(x: 388, y: 330))
arrow.move(to: NSPoint(x: 369, y: 347))
arrow.line(to: NSPoint(x: 388, y: 330))
arrow.line(to: NSPoint(x: 369, y: 313))
NSColor(calibratedRed: 0.23, green: 0.49, blue: 0.85, alpha: 1).setStroke()
arrow.stroke()

text("① 拖入应用程序     ② 从应用程序打开     ③ 点击顶部菜单栏图标", top: 266, height: 32,
     font: .systemFont(ofSize: 15, weight: .medium),
     color: NSColor(calibratedWhite: 0.24, alpha: 1))
text("首次打开被 macOS 拦截？先查看下方「安装说明」。", top: 309, height: 28,
     font: .systemFont(ofSize: 14), color: NSColor(calibratedWhite: 0.38, alpha: 1))
text("安装完成后，可在 Finder 边栏推出此磁盘。", top: 469, height: 24,
     font: .systemFont(ofSize: 12), color: NSColor(calibratedWhite: 0.44, alpha: 1))

canvas.unlockFocus()
guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to render installer background.\n", stderr)
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
} catch {
    fputs("Unable to save installer background: \(error)\n", stderr)
    exit(1)
}
