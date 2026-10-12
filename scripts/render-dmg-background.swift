#!/usr/bin/env swift

import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: render-dmg-background.swift OUTPUT.png\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let logicalWidth = 540
let logicalHeight = 360
let scale = 2

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: logicalWidth * scale,
    pixelsHigh: logicalHeight * scale,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not create the DMG background canvas.\n", stderr)
    exit(1)
}
bitmap.size = NSSize(width: logicalWidth, height: logicalHeight)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let canvas = NSRect(x: 0, y: 0, width: logicalWidth, height: logicalHeight)
let gradient = NSGradient(
    starting: NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1),
    ending: NSColor(red: 0.91, green: 0.92, blue: 0.94, alpha: 1)
)
gradient?.draw(in: canvas, angle: -90)

let prompt = "Drag to install" as NSString
let promptAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 18, weight: .medium),
    .foregroundColor: NSColor(red: 0.23, green: 0.25, blue: 0.28, alpha: 1)
]
let promptSize = prompt.size(withAttributes: promptAttributes)
prompt.draw(
    at: NSPoint(x: (CGFloat(logicalWidth) - promptSize.width) / 2, y: 205),
    withAttributes: promptAttributes
)

let arrowColor = NSColor(red: 0.15, green: 0.53, blue: 0.85, alpha: 1)
arrowColor.setStroke()

let shaft = NSBezierPath()
shaft.lineWidth = 4
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 205, y: 166))
shaft.line(to: NSPoint(x: 335, y: 166))
shaft.stroke()

let arrowHead = NSBezierPath()
arrowHead.lineWidth = 4
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
arrowHead.move(to: NSPoint(x: 319, y: 178))
arrowHead.line(to: NSPoint(x: 335, y: 166))
arrowHead.line(to: NSPoint(x: 319, y: 154))
arrowHead.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode the DMG background as PNG.\n", stderr)
    exit(1)
}

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try pngData.write(to: outputURL)
} catch {
    fputs("Could not write the DMG background: \(error.localizedDescription)\n", stderr)
    exit(1)
}
