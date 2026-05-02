#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

let outputDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let projectDirectory = outputDirectory.deletingLastPathComponent().deletingLastPathComponent()
let appIconDirectory = projectDirectory
    .appendingPathComponent("Sunpaper")
    .appendingPathComponent("Assets.xcassets")
    .appendingPathComponent("AppIcon.appiconset")

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xff) / 255
    let g = CGFloat((hex >> 8) & 0xff) / 255
    let b = CGFloat(hex & 0xff) / 255
    return CGColor(red: r, green: g, blue: b, alpha: alpha)
}

func gradient(_ colors: [CGColor], locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: locations
    )!
}

func pngData(from image: NSImage) -> Data {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:])
    else {
        fatalError("Could not encode PNG")
    }
    return data
}

func drawRoundedGradient(
    in ctx: CGContext,
    rect: CGRect,
    radius: CGFloat,
    colors: [CGColor],
    start: CGPoint,
    end: CGPoint,
    locations: [CGFloat]? = nil
) {
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.drawLinearGradient(
        gradient(colors, locations: locations),
        start: start,
        end: end,
        options: []
    )
    ctx.restoreGState()
}

func drawCapsule(
    in ctx: CGContext,
    center: CGPoint,
    length: CGFloat,
    thickness: CGFloat,
    angleDegrees: CGFloat,
    fill: CGColor,
    shadow: Bool = false
) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angleDegrees * .pi / 180)

    if shadow {
        ctx.setShadow(
            offset: CGSize(width: 0, height: thickness * 0.22),
            blur: thickness * 0.32,
            color: color(0x20110d, alpha: 0.24)
        )
    }

    let rect = CGRect(
        x: -length / 2,
        y: -thickness / 2,
        width: length,
        height: thickness
    )
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil))
    ctx.setFillColor(fill)
    ctx.fillPath()
    ctx.restoreGState()
}

func drawMark(in ctx: CGContext, size: CGFloat, scale: CGFloat) {
    let u = size / 1024
    let amber = color(0xffb33f)
    let amberLight = color(0xffc15b, alpha: 0.9)

    // Rays use one shared geometry system so the mark stays balanced at large sizes.
    let rayThickness = 50 * u
    drawCapsule(in: ctx, center: CGPoint(x: 512 * u, y: 404 * u), length: 102 * u, thickness: rayThickness, angleDegrees: 90, fill: amberLight, shadow: true)
    drawCapsule(in: ctx, center: CGPoint(x: 389 * u, y: 437 * u), length: 106 * u, thickness: rayThickness, angleDegrees: 55, fill: amberLight, shadow: true)
    drawCapsule(in: ctx, center: CGPoint(x: 635 * u, y: 437 * u), length: 106 * u, thickness: rayThickness, angleDegrees: -55, fill: amberLight, shadow: true)
    drawCapsule(in: ctx, center: CGPoint(x: 323 * u, y: 557 * u), length: 82 * u, thickness: rayThickness, angleDegrees: 0, fill: amberLight, shadow: true)
    drawCapsule(in: ctx, center: CGPoint(x: 701 * u, y: 557 * u), length: 82 * u, thickness: rayThickness, angleDegrees: 0, fill: amberLight, shadow: true)

    let horizonY = 628 * u
    let sunRadius = 104 * u
    let sunCenter = CGPoint(x: 512 * u, y: horizonY)

    // Sun body: clipped half-circle, no extra horizon hairline.
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: 0, width: size, height: horizonY))
    let sunRect = CGRect(
        x: sunCenter.x - sunRadius,
        y: sunCenter.y - sunRadius,
        width: sunRadius * 2,
        height: sunRadius * 2
    )
    ctx.addEllipse(in: sunRect)
    ctx.setFillColor(amber)
    ctx.fillPath()
    ctx.restoreGState()

    // Subtle highlight only on the sun face.
    ctx.saveGState()
    ctx.clip(to: CGRect(x: sunRect.minX, y: sunRect.minY, width: sunRect.width, height: sunRadius))
    ctx.addEllipse(in: sunRect)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([color(0xffcf72, alpha: 0.78), color(0xffa72f, alpha: 0.0)]),
        start: CGPoint(x: sunRect.midX, y: sunRect.minY),
        end: CGPoint(x: sunRect.midX, y: sunRect.maxY),
        options: []
    )
    ctx.restoreGState()

    // Horizon is one confident paper-like stroke with a soft underside.
    drawCapsule(
        in: ctx,
        center: CGPoint(x: 512 * u, y: 688 * u),
        length: 456 * u,
        thickness: 54 * u,
        angleDegrees: 0,
        fill: amber,
        shadow: true
    )

    drawCapsule(
        in: ctx,
        center: CGPoint(x: 512 * u, y: 674 * u),
        length: 392 * u,
        thickness: 6 * u,
        angleDegrees: 0,
        fill: color(0xffdf8f, alpha: 0.45),
        shadow: false
    )

    _ = scale
}

func renderIcon(size: CGFloat) -> NSImage {
    let pixelSize = Int(size.rounded())
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [.alphaFirst],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not create bitmap")
    }
    bitmap.size = NSSize(width: size, height: size)

    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create graphics context")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        fatalError("No graphics context")
    }

    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    let u = size / 1024
    let tile = CGRect(x: 48 * u, y: 48 * u, width: 928 * u, height: 928 * u)
    let radius = 220 * u

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 22 * u), blur: 38 * u, color: color(0x160b08, alpha: 0.30))
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(color(0x2a1718))
    ctx.fillPath()
    ctx.restoreGState()

    drawRoundedGradient(
        in: ctx,
        rect: tile,
        radius: radius,
        colors: [
            color(0x3b2538),
            color(0x6b3429),
            color(0xe96f24)
        ],
        start: CGPoint(x: tile.minX, y: tile.minY),
        end: CGPoint(x: tile.maxX, y: tile.maxY),
        locations: [0.0, 0.54, 1.0]
    )

    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()

    ctx.drawRadialGradient(
        gradient([color(0xff9a37, alpha: 0.50), color(0xff7a20, alpha: 0.0)]),
        startCenter: CGPoint(x: 690 * u, y: 710 * u),
        startRadius: 0,
        endCenter: CGPoint(x: 690 * u, y: 710 * u),
        endRadius: 430 * u,
        options: []
    )

    ctx.drawLinearGradient(
        gradient([color(0xffffff, alpha: 0.16), color(0xffffff, alpha: 0.0)]),
        start: CGPoint(x: tile.midX, y: tile.minY),
        end: CGPoint(x: tile.midX, y: tile.minY + 270 * u),
        options: []
    )

    drawMark(in: ctx, size: size, scale: u)
    ctx.restoreGState()

    // Beveled app-tile edge, restrained so it does not become the logo.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 8 * u, dy: 8 * u), cornerWidth: radius - 8 * u, cornerHeight: radius - 8 * u, transform: nil))
    ctx.setStrokeColor(color(0xffffff, alpha: 0.16))
    ctx.setLineWidth(2.0 * u)
    ctx.strokePath()
    ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 20 * u, dy: 20 * u), cornerWidth: radius - 20 * u, cornerHeight: radius - 20 * u, transform: nil))
    ctx.setStrokeColor(color(0x5c2417, alpha: 0.34))
    ctx.setLineWidth(8.0 * u)
    ctx.strokePath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(bitmap)
    return image
}

func composite(_ source: NSImage, size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    source.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1)
    image.unlockFocus()
    return image
}

func drawPreview(base icon: NSImage) -> NSImage {
    let canvas = NSImage(size: NSSize(width: 1800, height: 1120))
    canvas.lockFocus()

    NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.96, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 1800, height: 1120).fill()

    let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 34, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.10, alpha: 1)
    ]
    let captionAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 18, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 1)
    ]

    "Sunpaper app icon proposal".draw(at: NSPoint(x: 80, y: 1030), withAttributes: titleAttributes)
    "Cleaner source-backed sun/horizon mark, shown at launch-size and dock-size scales.".draw(at: NSPoint(x: 80, y: 994), withAttributes: captionAttributes)

    icon.draw(in: NSRect(x: 90, y: 210, width: 760, height: 760), from: .zero, operation: .sourceOver, fraction: 1)

    let panel = NSBezierPath(roundedRect: NSRect(x: 930, y: 202, width: 790, height: 768), xRadius: 34, yRadius: 34)
    NSColor.white.setFill()
    panel.fill()

    let darkPanel = NSBezierPath(roundedRect: NSRect(x: 990, y: 286, width: 670, height: 262), xRadius: 28, yRadius: 28)
    NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.09, alpha: 1).setFill()
    darkPanel.fill()

    let sizes: [CGFloat] = [256, 128, 64, 32, 16]
    var x: CGFloat = 1018
    let y: CGFloat = 720
    for size in sizes {
        icon.draw(in: NSRect(x: x, y: y, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1)
        "\(Int(size))".draw(at: NSPoint(x: x + max(0, size / 2 - 16), y: y - 34), withAttributes: captionAttributes)
        x += size + 46
    }

    x = 1018
    for size in sizes {
        icon.draw(in: NSRect(x: x, y: 358, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1)
        x += size + 46
    }

    let dock = NSBezierPath(roundedRect: NSRect(x: 1010, y: 250, width: 630, height: 104), xRadius: 32, yRadius: 32)
    NSColor(calibratedWhite: 1, alpha: 0.18).setFill()
    dock.fill()
    icon.draw(in: NSRect(x: 1268, y: 262, width: 80, height: 80), from: .zero, operation: .sourceOver, fraction: 1)

    canvas.unlockFocus()
    return canvas
}

func writeAppIconSet(from icon: NSImage, to directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    for size in [16, 32, 64, 128, 256, 512, 1024] {
        let image = renderIcon(size: CGFloat(size))
        let url = directory.appendingPathComponent("icon_\(size)x\(size).png")
        try pngData(from: image).write(to: url)
    }

    let contents = """
    {
      "images": [
        {
          "filename": "icon_16x16.png",
          "idiom": "mac",
          "scale": "1x",
          "size": "16x16"
        },
        {
          "filename": "icon_32x32.png",
          "idiom": "mac",
          "scale": "2x",
          "size": "16x16"
        },
        {
          "filename": "icon_32x32.png",
          "idiom": "mac",
          "scale": "1x",
          "size": "32x32"
        },
        {
          "filename": "icon_64x64.png",
          "idiom": "mac",
          "scale": "2x",
          "size": "32x32"
        },
        {
          "filename": "icon_128x128.png",
          "idiom": "mac",
          "scale": "1x",
          "size": "128x128"
        },
        {
          "filename": "icon_256x256.png",
          "idiom": "mac",
          "scale": "2x",
          "size": "128x128"
        },
        {
          "filename": "icon_256x256.png",
          "idiom": "mac",
          "scale": "1x",
          "size": "256x256"
        },
        {
          "filename": "icon_512x512.png",
          "idiom": "mac",
          "scale": "2x",
          "size": "256x256"
        },
        {
          "filename": "icon_512x512.png",
          "idiom": "mac",
          "scale": "1x",
          "size": "512x512"
        },
        {
          "filename": "icon_1024x1024.png",
          "idiom": "mac",
          "scale": "2x",
          "size": "512x512"
        }
      ],
      "info": {
        "author": "xcode",
        "version": 1
      }
    }

    """
    try contents.write(
        to: directory.appendingPathComponent("Contents.json"),
        atomically: true,
        encoding: .utf8
    )
}

let icon = renderIcon(size: 1024)
let iconURL = outputDirectory.appendingPathComponent("sunpaper-icon-proposal.png")
try pngData(from: icon).write(to: iconURL)

let preview = drawPreview(base: icon)
let previewURL = outputDirectory.appendingPathComponent("sunpaper-icon-proposal-preview.png")
try pngData(from: preview).write(to: previewURL)

for size in [16, 32, 64, 128, 256, 512] {
    let scaled = renderIcon(size: CGFloat(size))
    let url = outputDirectory.appendingPathComponent("sunpaper-icon-proposal-\(size).png")
    try pngData(from: scaled).write(to: url)
}

print("Wrote \(iconURL.path)")
print("Wrote \(previewURL.path)")

if CommandLine.arguments.contains("--asset-catalog") {
    try writeAppIconSet(from: icon, to: appIconDirectory)
    print("Updated \(appIconDirectory.path)")
}
