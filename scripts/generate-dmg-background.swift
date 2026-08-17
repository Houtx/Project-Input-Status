#!/usr/bin/env swift

import AppKit

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("Usage: generate-dmg-background.swift <AppIcon.icns> <output.png>\n".utf8)
    )
    exit(1)
}

let iconURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let canvasSize = NSSize(width: 760, height: 480)

guard let appIcon = NSImage(contentsOf: iconURL) else {
    FileHandle.standardError.write(Data("Unable to load app icon.\n".utf8))
    exit(1)
}

func color(_ red: Int, _ green: Int, _ blue: Int, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat(red) / 255,
        green: CGFloat(green) / 255,
        blue: CGFloat(blue) / 255,
        alpha: alpha
    )
}

func drawText(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .left
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    (text as NSString).draw(
        in: rect,
        withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    )
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    FileHandle.standardError.write(Data("Unable to create bitmap canvas.\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
defer { NSGraphicsContext.restoreGraphicsState() }

context.shouldAntialias = true
context.imageInterpolation = .high

color(239, 243, 244).setFill()
NSRect(origin: .zero, size: canvasSize).fill()

color(21, 29, 31).setFill()
NSRect(x: 0, y: 380, width: 760, height: 100).fill()

appIcon.draw(
    in: NSRect(x: 36, y: 397, width: 66, height: 66),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)

drawText(
    "安装 Input Status",
    in: NSRect(x: 120, y: 424, width: 570, height: 34),
    font: .systemFont(ofSize: 27, weight: .bold),
    color: .white
)
drawText(
    "拖动一次，即可在桌面查看 AI.INPUT.IM 服务状态",
    in: NSRect(x: 121, y: 398, width: 570, height: 24),
    font: .systemFont(ofSize: 14, weight: .medium),
    color: color(195, 208, 207)
)

drawText(
    "1  拖动 InputStatus",
    in: NSRect(x: 70, y: 330, width: 230, height: 28),
    font: .systemFont(ofSize: 16, weight: .semibold),
    color: color(27, 38, 40),
    alignment: .center
)
drawText(
    "2  放入“应用程序”",
    in: NSRect(x: 460, y: 330, width: 230, height: 28),
    font: .systemFont(ofSize: 16, weight: .semibold),
    color: color(27, 38, 40),
    alignment: .center
)

let arrow = NSBezierPath()
arrow.lineWidth = 8
arrow.lineCapStyle = .round
arrow.move(to: NSPoint(x: 302, y: 250))
arrow.line(to: NSPoint(x: 454, y: 250))
color(22, 163, 108).setStroke()
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 454, y: 250))
arrowHead.line(to: NSPoint(x: 428, y: 269))
arrowHead.line(to: NSPoint(x: 428, y: 231))
arrowHead.close()
color(22, 163, 108).setFill()
arrowHead.fill()

let securityPanel = NSBezierPath(
    roundedRect: NSRect(x: 32, y: 26, width: 696, height: 105),
    xRadius: 14,
    yRadius: 14
)
color(220, 228, 228).setFill()
securityPanel.fill()

let warningCircle = NSBezierPath(ovalIn: NSRect(x: 55, y: 61, width: 34, height: 34))
color(208, 126, 32).setFill()
warningCircle.fill()
drawText(
    "!",
    in: NSRect(x: 55, y: 66, width: 34, height: 27),
    font: .systemFont(ofSize: 20, weight: .bold),
    color: .white,
    alignment: .center
)

drawText(
    "首次打开若提示无法验证开发者",
    in: NSRect(x: 108, y: 86, width: 580, height: 25),
    font: .systemFont(ofSize: 15, weight: .semibold),
    color: color(33, 43, 45)
)
drawText(
    "前往 系统设置 → 隐私与安全性，点击“仍要打开”",
    in: NSRect(x: 108, y: 58, width: 580, height: 26),
    font: .systemFont(ofSize: 15, weight: .medium),
    color: color(33, 43, 45)
)
drawText(
    "这是未公证版本的 macOS 标准确认步骤，仅需操作一次。",
    in: NSRect(x: 108, y: 37, width: 580, height: 20),
    font: .systemFont(ofSize: 12, weight: .regular),
    color: color(89, 102, 103)
)

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Unable to encode background image.\n".utf8))
    exit(1)
}

try pngData.write(to: outputURL, options: .atomic)
print("Generated: \(outputURL.path)")
