#!/usr/bin/swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: generate-icon.swift OUTPUT.png\n".utf8))
    exit(2)
}

let pixelSize = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Unable to allocate icon bitmap")
}

bitmap.size = NSSize(width: pixelSize, height: pixelSize)
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create icon graphics context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

let canvas = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
NSColor.clear.setFill()
canvas.fill()

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
shadow.shadowBlurRadius = 36
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()

let tileRect = NSRect(x: 72, y: 78, width: 880, height: 880)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 210, yRadius: 210)
NSColor(calibratedRed: 0.055, green: 0.071, blue: 0.082, alpha: 1).setFill()
tile.fill()

NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let innerBorder = NSBezierPath(
    roundedRect: tileRect.insetBy(dx: 12, dy: 12),
    xRadius: 198,
    yRadius: 198
)
innerBorder.lineWidth = 10
NSColor.white.withAlphaComponent(0.08).setStroke()
innerBorder.stroke()

let waveform = NSBezierPath()
waveform.lineWidth = 68
waveform.lineCapStyle = .round
waveform.lineJoinStyle = .round
waveform.move(to: NSPoint(x: 176, y: 510))
waveform.line(to: NSPoint(x: 302, y: 510))
waveform.line(to: NSPoint(x: 372, y: 682))
waveform.line(to: NSPoint(x: 456, y: 332))
waveform.line(to: NSPoint(x: 548, y: 674))
waveform.line(to: NSPoint(x: 638, y: 442))
waveform.line(to: NSPoint(x: 712, y: 526))
waveform.line(to: NSPoint(x: 846, y: 526))
NSColor(calibratedRed: 0.31, green: 0.91, blue: 0.57, alpha: 1).setStroke()
waveform.stroke()

let statusRing = NSBezierPath(ovalIn: NSRect(x: 690, y: 190, width: 170, height: 170))
NSColor(calibratedRed: 0.055, green: 0.071, blue: 0.082, alpha: 1).setFill()
statusRing.fill()

let statusDot = NSBezierPath(ovalIn: NSRect(x: 719, y: 219, width: 112, height: 112))
NSColor(calibratedRed: 0.31, green: 0.91, blue: 0.57, alpha: 1).setFill()
statusDot.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode icon PNG")
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
