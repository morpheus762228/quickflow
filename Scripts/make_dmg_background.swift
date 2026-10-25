// QuickFlow DMG background generator
// Draws the installer window backdrop: title, drag arrow, first-launch hint.
//
// Usage: swift Scripts/make_dmg_background.swift <output.png> [scale]
//
// The artwork is sized to the window's CONTENT area, not its frame: a 600x400
// Finder window has a 28 pt title bar, leaving 600x372 pt for content. Finder
// draws the background image into the content view, so matching that size keeps
// the arrow on the same line as the icons at 1x and 2x. Icon coordinates in
// Scripts/dmg_settings.py must stay in sync with ICON_ROW_Y here.

import SwiftUI
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
let renderScale = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) ?? 1 : 1

let W: CGFloat = 600
let H: CGFloat = 372          // content height of a 600x400 window
let ICON_ROW_Y: CGFloat = 176 // must match icon_locations in dmg_settings.py

let blue = Color(.sRGB, red: 0.325, green: 0.545, blue: 1.000, opacity: 1)
let violet = Color(.sRGB, red: 0.435, green: 0.290, blue: 0.960, opacity: 1)
let ink = Color(.sRGB, red: 0.110, green: 0.114, blue: 0.133, opacity: 1)
let grey = Color(.sRGB, red: 0.420, green: 0.435, blue: 0.478, opacity: 1)
let faint = Color(.sRGB, red: 0.545, green: 0.560, blue: 0.600, opacity: 1)

struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [
                Color(.sRGB, red: 0.988, green: 0.992, blue: 1.000, opacity: 1),
                Color(.sRGB, red: 0.933, green: 0.946, blue: 0.976, opacity: 1),
            ], startPoint: .top, endPoint: .bottom)

            RadialGradient(colors: [blue.opacity(0.10), violet.opacity(0.0)],
                           center: .init(x: 0.5, y: 0.44),
                           startRadius: 8, endRadius: 260)

            // Title block, kept clear of the icon row.
            VStack(spacing: 6) {
                Text("QuickFlow")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundColor(ink)
                Text("Drag QuickFlow into Applications")
                    .font(.system(size: 13.5))
                    .foregroundColor(grey)
                Capsule()
                    .fill(LinearGradient(colors: [blue, violet], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 52, height: 3)
                    .padding(.top, 5)
            }
            .position(x: W / 2, y: 58)

            // Arrow between the app icon (x=160) and Applications (x=440).
            // 128 pt icons leave a 152 pt gap; 120 pt of arrow keeps 16 pt clear.
            Arrow()
                .fill(violet)
                .frame(width: 120, height: 18)
                .position(x: 300, y: ICON_ROW_Y)

            VStack(spacing: 5) {
                Text("First launch: right-click QuickFlow, choose Open, then Open again.")
                    .font(.system(size: 11))
                    .foregroundColor(faint)
                Text("100% on this Mac  ·  no account  ·  no cloud")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(faint.opacity(0.85))
            }
            .position(x: W / 2, y: H - 34)
        }
        .frame(width: W, height: H)
        .clipped()
    }
}

/// A filled horizontal arrow with a solid head, drawn inside its frame.
struct Arrow: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.midY
        let headLength: CGFloat = 15
        let thickness: CGFloat = 4
        let headHalf: CGFloat = 9

        p.addRect(CGRect(x: rect.minX,
                         y: midY - thickness / 2,
                         width: rect.width - headLength,
                         height: thickness))
        p.move(to: CGPoint(x: rect.maxX, y: midY))
        p.addLine(to: CGPoint(x: rect.maxX - headLength, y: midY - headHalf))
        p.addLine(to: CGPoint(x: rect.maxX - headLength, y: midY + headHalf))
        p.closeSubpath()
        return p
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Backdrop())
    renderer.scale = renderScale
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("render failed")
    }
    try! png.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath) (\(rep.pixelsWide)x\(rep.pixelsHigh) @\(renderScale)x)")
}
