// QuickFlow placeholder icon generator
// Draws a 1024x1024 macOS-style app icon: gradient squircle + voice waveform.
// Usage: swift Scripts/make_icon.swift <output.png>

import AppKit
import CoreGraphics

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let S: CGFloat = 1024
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)

func superellipse(_ r: CGRect, n: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let a = r.width / 2, b = r.height / 2
    let cx = r.midX, cy = r.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = cy + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    p.closeSubpath()
    return p
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = NSSize(width: S, height: S)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.clear(CGRect(x: 0, y: 0, width: S, height: S))

let shape = superellipse(rect, n: 4.6)

// Soft drop shadow under the squircle
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 46,
              color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.addPath(shape)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()

// Gradient body
ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
let body = NSGradient(colors: [
    NSColor(srgbRed: 0.325, green: 0.545, blue: 1.000, alpha: 1.0),
    NSColor(srgbRed: 0.435, green: 0.290, blue: 0.960, alpha: 1.0),
])!
body.draw(in: rect, angle: -52)

// Top-left sheen (linear to avoid radial center artifacts)
let sheen = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.26),
    NSColor.white.withAlphaComponent(0.04),
    NSColor.white.withAlphaComponent(0.0),
])!
sheen.draw(in: rect, angle: -125)

// Bottom-right cool tint
let tint = NSGradient(colors: [
    NSColor(srgbRed: 0.18, green: 0.10, blue: 0.55, alpha: 0.0),
    NSColor(srgbRed: 0.18, green: 0.10, blue: 0.55, alpha: 0.35),
])!
tint.draw(in: rect, angle: -52)

// Inner edge light
ctx.addPath(shape)
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
ctx.setLineWidth(6)
ctx.strokePath()
ctx.restoreGState()

// Waveform bars
let heights: [CGFloat] = [0.34, 0.58, 0.84, 0.58, 0.34]
let barW: CGFloat = 58
let gap: CGFloat = 34
let totalW = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
let maxH: CGFloat = 470
var x = rect.midX - totalW / 2

for h in heights {
    let bh = maxH * h
    let bar = CGRect(x: x, y: rect.midY - bh / 2, width: barW, height: bh)
    let barPath = CGPath(roundedRect: bar, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18,
                  color: NSColor.black.withAlphaComponent(0.22).cgColor)
    let barGrad = NSGradient(colors: [
        NSColor.white,
        NSColor(srgbRed: 0.90, green: 0.94, blue: 1.0, alpha: 1.0),
    ])!
    ctx.addPath(barPath)
    ctx.clip()
    barGrad.draw(in: bar, angle: -90)
    ctx.restoreGState()
    x += barW + gap
}

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) \(png.count) bytes")
