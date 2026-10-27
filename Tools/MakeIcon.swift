// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import AppKit

guard CommandLine.arguments.count == 2 else { fatalError("Usage: MakeIcon.swift OUTPUT.iconset") }
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

// Original app artwork: two overlapping language cards, using system text.
func image(size: Int) -> Data {
    let value = CGFloat(size)
    let image = NSImage(size: NSSize(width: value, height: value))
    image.lockFocus()
    let scale = value / 512
    let background = NSBezierPath(roundedRect: NSRect(x: 28 * scale, y: 28 * scale,
        width: 456 * scale, height: 456 * scale), xRadius: 108 * scale, yRadius: 108 * scale)
    NSColor(calibratedRed: 0.13, green: 0.33, blue: 0.69, alpha: 1).setFill()
    background.fill()
    NSColor(calibratedRed: 0.66, green: 0.81, blue: 1, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 92 * scale, y: 190 * scale, width: 215 * scale,
        height: 220 * scale), xRadius: 34 * scale, yRadius: 34 * scale).fill()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 210 * scale, y: 98 * scale, width: 215 * scale,
        height: 220 * scale), xRadius: 34 * scale, yRadius: 34 * scale).fill()
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 126 * scale, weight: .semibold),
        .foregroundColor: NSColor(calibratedRed: 0.08, green: 0.23, blue: 0.50, alpha: 1),
    ]
    ("A" as NSString).draw(at: NSPoint(x: 151 * scale, y: 229 * scale), withAttributes: attributes)
    ("文" as NSString).draw(at: NSPoint(x: 255 * scale, y: 134 * scale), withAttributes: attributes)
    image.unlockFocus()
    let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return representation.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try image(size: points).write(to: directory.appendingPathComponent("icon_\(points)x\(points).png"))
    try image(size: points * 2).write(to: directory.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
