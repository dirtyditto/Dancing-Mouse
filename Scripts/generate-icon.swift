#!/usr/bin/env swift
//
// generate-icon.swift
// Generates the Dancing Mouse app icon as an .icns file using Core Graphics.
// Draws a stylized cursor with a sparkle trail.
//
// Usage: swift Scripts/generate-icon.swift <output-dir>
//   Produces: <output-dir>/AppIcon.icns

import Cocoa
import CoreGraphics

let outputDir: String
if CommandLine.arguments.count > 1 {
    outputDir = CommandLine.arguments[1]
} else {
    outputDir = "."
}

/// Renders the icon at a given size into a CGContext.
func drawIcon(in ctx: CGContext, size: CGFloat) {
    let s = size

    // --- Background: rounded rect gradient ---
    let cornerRadius = s * 0.22
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Purple-to-indigo gradient
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        CGColor(srgbRed: 0.38, green: 0.15, blue: 0.75, alpha: 1.0),
        CGColor(srgbRed: 0.18, green: 0.08, blue: 0.45, alpha: 1.0)
    ] as CFArray
    let locations: [CGFloat] = [0.0, 1.0]

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: locations) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    }
    ctx.restoreGState()

    // --- Cursor arrow ---
    let cursorScale = s / 512.0
    ctx.saveGState()
    ctx.translateBy(x: s * 0.18, y: s * 0.12)
    ctx.scaleBy(x: cursorScale, y: cursorScale)

    // White cursor arrow shape
    let cursorPath = CGMutablePath()
    cursorPath.move(to: CGPoint(x: 60, y: 40))
    cursorPath.addLine(to: CGPoint(x: 60, y: 340))
    cursorPath.addLine(to: CGPoint(x: 130, y: 270))
    cursorPath.addLine(to: CGPoint(x: 195, y: 370))
    cursorPath.addLine(to: CGPoint(x: 235, y: 350))
    cursorPath.addLine(to: CGPoint(x: 170, y: 250))
    cursorPath.addLine(to: CGPoint(x: 260, y: 250))
    cursorPath.closeSubpath()

    // Shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 4 * cursorScale, height: -4 * cursorScale), blur: 12 * cursorScale, color: CGColor(gray: 0, alpha: 0.5))
    ctx.setFillColor(CGColor.white)
    ctx.addPath(cursorPath)
    ctx.fillPath()
    ctx.restoreGState()

    // Cursor fill
    ctx.setFillColor(CGColor.white)
    ctx.addPath(cursorPath)
    ctx.fillPath()

    // Cursor outline
    ctx.setStrokeColor(CGColor(gray: 0.2, alpha: 0.5))
    ctx.setLineWidth(3.0)
    ctx.addPath(cursorPath)
    ctx.strokePath()

    ctx.restoreGState()

    // --- Sparkle/trail dots ---
    let sparkles: [(x: CGFloat, y: CGFloat, radius: CGFloat, alpha: CGFloat)] = [
        (0.62, 0.25, 0.055, 0.9),
        (0.72, 0.38, 0.045, 0.8),
        (0.78, 0.52, 0.038, 0.7),
        (0.82, 0.65, 0.030, 0.55),
        (0.76, 0.75, 0.025, 0.4),
        (0.68, 0.82, 0.020, 0.3),
        (0.55, 0.44, 0.035, 0.6),
        (0.50, 0.60, 0.028, 0.5),
    ]

    for sparkle in sparkles {
        let cx = sparkle.x * s
        let cy = sparkle.y * s
        let r = sparkle.radius * s
        let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        let color = CGColor(srgbRed: 0.7, green: 0.85, blue: 1.0, alpha: sparkle.alpha)
        ctx.setFillColor(color)
        ctx.fillEllipse(in: rect)
    }

    // --- Star sparkle accent ---
    func drawStar(ctx: CGContext, center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat, color: CGColor) {
        let points = 4
        let path = CGMutablePath()
        for i in 0..<(points * 2) {
            let angle = Double(i) * .pi / Double(points) - .pi / 2
            let r = i % 2 == 0 ? outerRadius : innerRadius
            let pt = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        ctx.setFillColor(color)
        ctx.addPath(path)
        ctx.fillPath()
    }

    drawStar(ctx: ctx, center: CGPoint(x: s * 0.72, y: s * 0.22),
             outerRadius: s * 0.06, innerRadius: s * 0.02,
             color: CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.9))
    drawStar(ctx: ctx, center: CGPoint(x: s * 0.85, y: s * 0.48),
             outerRadius: s * 0.04, innerRadius: s * 0.015,
             color: CGColor(srgbRed: 0.8, green: 0.9, blue: 1.0, alpha: 0.7))
}

/// Render icon at a specific pixel size and return as NSImage.
func renderIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    if let ctx = NSGraphicsContext.current?.cgContext {
        // Flip coordinate system (CG is bottom-up, we draw top-down)
        ctx.translateBy(x: 0, y: s)
        ctx.scaleBy(x: 1, y: -1)
        drawIcon(in: ctx, size: s)
    }
    image.unlockFocus()
    return image
}

// --- Generate iconset and convert to .icns ---

let iconsetPath = "\(outputDir)/AppIcon.iconset"
let icnsPath = "\(outputDir)/AppIcon.icns"

// Create iconset directory
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for entry in sizes {
    let image = renderIcon(size: entry.pixels)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to render \(entry.name)\n", stderr)
        continue
    }
    let filePath = "\(iconsetPath)/\(entry.name).png"
    try png.write(to: URL(fileURLWithPath: filePath))
}

// Convert iconset to icns using iconutil
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath, "-o", icnsPath]
try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Generated \(icnsPath)")
    try? fm.removeItem(atPath: iconsetPath)
} else {
    fputs("iconutil failed with exit code \(process.terminationStatus)\n", stderr)
    exit(1)
}
