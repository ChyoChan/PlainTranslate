// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import Foundation
import CoreGraphics
import ImageIO

guard CommandLine.arguments.count == 3 else { fatalError("Usage: MakeIcon.swift MASTER.png OUTPUT.iconset") }
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let master = CGImageSourceCreateImageAtIndex(source, 0, nil),
      master.width == 1024, master.height == 1024 else {
    fatalError("The app icon master must be a readable 1024 × 1024 image.")
}
let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

// The committed master keeps normal builds independent of SVG renderers and fonts.
func image(size: Int) -> Data {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: size, height: size,
              bitsPerComponent: 8, bytesPerRow: size * 4, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("Could not create the icon drawing context.")
    }
    context.interpolationQuality = .high
    context.draw(master, in: CGRect(x: 0, y: 0, width: size, height: size))
    let data = NSMutableData()
    guard let rendered = context.makeImage(),
          let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
        fatalError("Could not encode the app icon.")
    }
    CGImageDestinationAddImage(destination, rendered, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not finish the icon PNG.") }
    return data as Data
}

for points in [16, 32, 128, 256, 512] {
    try image(size: points).write(to: directory.appendingPathComponent("icon_\(points)x\(points).png"))
    try image(size: points * 2).write(to: directory.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
