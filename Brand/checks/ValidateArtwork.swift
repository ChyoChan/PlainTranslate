// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors
// Run on macOS: swift checks/ValidateArtwork.swift PATH_TO_KIT
import AppKit
import ImageIO
import PDFKit

precondition(CommandLine.arguments.count == 2)
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
func bitmap(_ relative: String, _ width: Int, _ height: Int) throws -> NSBitmapImageRep {
    let image = NSBitmapImageRep(data: try Data(contentsOf: root.appendingPathComponent(relative)))!
    precondition(image.pixelsWide == width && image.pixelsHigh == height, relative)
    return image
}
func color(_ image: NSBitmapImageRep, _ x: Int, _ y: Int) -> NSColor {
    precondition(image.bitsPerSample == 8 && image.samplesPerPixel >= 3)
    var samples = [Int](repeating: 0, count: image.samplesPerPixel)
    samples.withUnsafeMutableBufferPointer { image.getPixel($0.baseAddress!, atX: x, y: y) }
    return NSColor(srgbRed: CGFloat(samples[0]) / 255,
                   green: CGFloat(samples[1]) / 255,
                   blue: CGFloat(samples[2]) / 255,
                   alpha: image.hasAlpha ? CGFloat(samples.last!) / 255 : 1)
}
let icon = try bitmap("app/PlainTranslate-1024.png", 1024, 1024)
precondition(color(icon, 0, 0).alphaComponent == 0, "Keep the outer tile corners transparent")
let background = color(icon, 128, 128)
precondition(abs(background.redComponent - 0) < 0.02)
precondition(abs(background.greenComponent - 0) < 0.02)
precondition(abs(background.blueComponent - 0) < 0.02)
let stem = color(icon, 300, 700)
precondition(stem.redComponent > 0.98 && stem.greenComponent > 0.98 && stem.blueComponent > 0.98)
let counter = color(icon, 512, 350)
precondition(abs(counter.greenComponent - background.greenComponent) < 0.01, "The T must reveal the tile colour")
let small = try bitmap("png/plaintranslate-symbol-small.png", 256, 256)
precondition(color(small, 128, 80).alphaComponent == 0)
precondition(color(small, 128, 120).alphaComponent == 0)
precondition(color(small, 60, 190).alphaComponent > 0.98)
let menu = try bitmap("app/BrandMarkTemplate.png", 18, 18)
_ = try bitmap("app/BrandMarkTemplate@2x.png", 36, 36)
precondition(color(menu, 9, 5).alphaComponent < 0.05, "Small-size T must stay open")
precondition(color(menu, 3, 13).alphaComponent > 0.9, "Menu icon must retain the P stem")
for size in [16, 32, 64, 128, 256, 512, 1024] {
    _ = try bitmap("app/PlainTranslate-\(size).png", size, size)
}
for size in [16, 32, 48] {
    _ = try bitmap("web/favicon-\(size).png", size, size)
}
_ = try bitmap("web/apple-touch-icon.png", 180, 180)
_ = try bitmap("web/icon-192.png", 192, 192)
_ = try bitmap("web/icon-512.png", 512, 512)
let mask = try bitmap("web/maskable-512.png", 512, 512)
precondition(color(mask, 0, 0).alphaComponent > 0.98, "Maskable tile must fill its canvas")
let icnsURL = root.appendingPathComponent("app/PlainTranslate.icns")
let source = CGImageSourceCreateWithURL(icnsURL as CFURL, nil)!
let sizes = Set((0..<CGImageSourceGetCount(source)).map { CGImageSourceCreateImageAtIndex(source, $0, nil)!.width })
precondition(Set([16, 32, 64, 128, 256, 512, 1024]).isSubset(of: sizes))
let guide = PDFDocument(url: root.appendingPathComponent("GUIDELINES.pdf"))!
precondition(guide.pageCount == 1, "The quick guide must remain one page")
print("Artwork validation passed: icon sizes, palette, transparent counters, menu template, ICNS, web assets and one-page PDF.")
