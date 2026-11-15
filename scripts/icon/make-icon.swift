// Draws the Sift icon: a stack of cards, the top card lifted, with a warm
// picture block (owner's pick "D deck", 2026-11-15). One drawing, two
// outputs:
//   Sift/Resources/AppIcon.icns  (macOS: 824-of-1024 rounded square, shadow)
//   prototypes/ios-deck/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//                                 (iOS: full bleed 1024, no alpha; iOS rounds it)
// Run from the repo root: swift scripts/icon/make-icon.swift
import AppKit

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
func round(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// The plate and the cards in a square of side `s` at `origin`.
func drawIcon(_ c: CGContext, in plate: CGRect) {
    let s = plate.width
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: plate.minX + x * s, y: plate.minY + y * s, width: w * s, height: h * s)
    }
    let g = CGGradient(colorsSpace: nil, colors: [rgb(54, 56, 64), rgb(22, 23, 28)] as CFArray, locations: [0, 1])!
    c.saveGState()
    c.drawLinearGradient(g, start: CGPoint(x: 0, y: plate.maxY), end: CGPoint(x: 0, y: plate.minY), options: [])
    c.restoreGState()
    // The stack (owner: equidistant, shrinking as they fade). Each card
    // behind is `shrink` times the one in front (width and height, centred
    // on the same vertical axis), its top edge `rise` higher, and fainter by
    // the same step. The whole stack, from the front card's foot to the back
    // card's top edge, is centred in the plate.
    let w = 0.64, h = 0.46, rise = 0.07, shrink = 0.86
    let steps = [0.0, 1.0, 2.0]
    let top = h + rise * 2                         // stack height
    let y0 = (1 - top) / 2                         // front card's foot
    func card(_ step: Double) -> CGRect {
        let k = pow(shrink, step)
        let cw = w * k, ch = h * k
        let cardTop = y0 + h + rise * step
        return R((1 - cw) / 2, cardTop - ch, cw, ch)
    }
    for (step, alpha) in zip(steps.reversed(), [0.28, 0.64]) where step > 0 {
        let k = pow(shrink, step)
        c.setFillColor(rgb(255, 255, 255, alpha)); c.addPath(round(card(step), 0.062 * s * k)); c.fillPath()
    }
    // The front card and what is on it, placed relative to the card.
    let front = card(0)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -0.012 * s), blur: 0.04 * s, color: rgb(0, 0, 0, 0.5))
    c.setFillColor(rgb(250, 250, 250)); c.addPath(round(front, 0.062 * s)); c.fillPath()
    c.restoreGState()
    func on(_ x: Double, _ y: Double, _ cw: Double, _ ch: Double) -> CGRect {
        CGRect(x: front.minX + x * s, y: front.minY + y * s, width: cw * s, height: ch * s)
    }
    c.setFillColor(rgb(255, 149, 0)); c.addPath(round(on(0.06, 0.225, 0.52, 0.18), 0.03 * s)); c.fillPath()
    c.setFillColor(rgb(40, 40, 48, 0.85)); c.addPath(round(on(0.06, 0.135, 0.42, 0.042), 0.021 * s)); c.fillPath()
    c.setFillColor(rgb(40, 40, 48, 0.35)); c.addPath(round(on(0.06, 0.055, 0.29, 0.042), 0.021 * s)); c.fillPath()
}

func bitmap(_ px: Int, alpha: Bool, draw: (CGContext, CGFloat) -> Void) -> NSBitmapImageRep {
    // iOS wants an icon without an alpha channel: noneSkipLast then.
    let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
    let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
    draw(c, CGFloat(px))
    return NSBitmapImageRep(cgImage: c.makeImage()!)
}

let root = FileManager.default.currentDirectoryPath

// iOS: full bleed, opaque.
let ios = bitmap(1024, alpha: false) { c, s in drawIcon(c, in: CGRect(x: 0, y: 0, width: s, height: s)) }
let iosDir = "\(root)/prototypes/ios-deck/App/Assets.xcassets/AppIcon.appiconset"
try! ios.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(iosDir)/AppIcon.png"))

// macOS: Apple's grid, 824 of 1024, rounded, with a soft shadow.
func mac(_ px: Int) -> NSBitmapImageRep {
    bitmap(px, alpha: true) { c, s in
        let k = s / 1024
        let plate = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
        let shape = round(plate, 185 * k)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 28 * k, color: rgb(0, 0, 0, 0.35))
        c.addPath(shape); c.setFillColor(rgb(22, 23, 28)); c.fillPath()
        c.restoreGState()
        c.addPath(shape); c.clip()
        drawIcon(c, in: plate)
    }
}
let tmp = FileManager.default.temporaryDirectory.appending(path: "Sift-\(UUID().uuidString).iconset")
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! mac(px).representation(using: .png, properties: [:])!.write(to: tmp.appending(path: "icon_\(name).png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", tmp.path, "-o", "\(root)/Sift/Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: tmp)
print(p.terminationStatus == 0 ? "ok" : "iconutil failed")
