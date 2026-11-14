// Draws the demo mode placeholder thumbnails: a flat color, two soft
// circles and one letter. No photos, no logos.
//
// Usage: swift scripts/demo/make-images.swift <manifest.json> <output folder>
// make-data.py writes the manifest and runs this.

import AppKit
import Foundation

struct Item: Decodable {
    let file: String
    let color: String
    let letter: String
    let shape: String
    let seed: Int
}

func color(_ hex: String, lighten: CGFloat = 0) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: String(hex.dropFirst())).scanHexInt64(&v)
    let r = CGFloat((v >> 16) & 0xFF) / 255, g = CGFloat((v >> 8) & 0xFF) / 255, b = CGFloat(v & 0xFF) / 255
    return NSColor(srgbRed: r + (1 - r) * lighten, green: g + (1 - g) * lighten, blue: b + (1 - b) * lighten, alpha: 1)
}

let args = CommandLine.arguments
guard args.count == 3, let data = FileManager.default.contents(atPath: args[1]) else {
    FileHandle.standardError.write(Data("usage: make-images.swift <manifest.json> <folder>\n".utf8))
    exit(1)
}
let items = try JSONDecoder().decode([Item].self, from: data)
let folder = URL(filePath: args[2], directoryHint: .isDirectory)

for item in items {
    let size: CGSize = switch item.shape {
    case "square": CGSize(width: 240, height: 240)
    case "avatar": CGSize(width: 96, height: 96)
    default: CGSize(width: 320, height: 180)
    }
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = CGRect(origin: .zero, size: size)
    var s = item.seed
    func next() -> CGFloat { s = (s &* 1103515245 &+ 12345) & 0x7FFFFFFF; return CGFloat(s % 1000) / 1000 }

    // Background: the theme color, a little lighter or darker per link.
    color(item.color, lighten: 0.05 + next() * 0.25).setFill()
    rect.fill()
    // Two circles in a lighter shade.
    for _ in 0..<2 {
        let d = size.height * (0.6 + next() * 0.8)
        let circle = CGRect(x: next() * size.width - d / 2, y: next() * size.height - d / 2, width: d, height: d)
        color(item.color, lighten: 0.45).withAlphaComponent(0.35).setFill()
        NSBezierPath(ovalIn: circle).fill()
    }
    // A video gets a play triangle in the corner.
    if item.shape == "video" {
        let path = NSBezierPath()
        let x = size.width - 46, y: CGFloat = 16
        path.move(to: CGPoint(x: x, y: y)); path.line(to: CGPoint(x: x, y: y + 28)); path.line(to: CGPoint(x: x + 24, y: y + 14)); path.close()
        NSColor.white.withAlphaComponent(0.85).setFill()
        path.fill()
    }
    let font = NSFont.systemFont(ofSize: size.height * (item.shape == "avatar" ? 0.5 : 0.42), weight: .bold)
    let text = NSAttributedString(string: item.letter, attributes: [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.92)])
    let t = text.size()
    text.draw(at: CGPoint(x: (size.width - t.width) / 2, y: (size.height - t.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    if let png = rep.representation(using: .png, properties: [:]) {
        try png.write(to: folder.appending(path: item.file))
    }
}
print("\(items.count) images")
