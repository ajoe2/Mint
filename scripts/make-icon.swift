// Draws Mint's app icon (a white mint sprig on a dark mint-leaf-green tile) in every size
// the asset catalog needs. Run from the repository root:
//
//     swift scripts/make-icon.swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputFolder = URL(fileURLWithPath: "Mint/Assets.xcassets/AppIcon.appiconset")

// MARK: - Drawing (in a 1024 × 1024 space, y pointing up)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// One mint leaf: an oval that's widest below the middle and comes to a point, with saw
/// teeth along each edge.
struct Leaf {
    var base: CGPoint
    /// Which way the leaf points: 0 is right, 90 is up.
    var degrees: CGFloat
    var length: CGFloat
    /// Half the width at the widest point, as a fraction of the length.
    var halfWidth: CGFloat = 0.33

    /// The point `t` of the way from base to tip and `side` of the way out to the widest edge
    /// (positive is left, looking toward the tip).
    func point(_ t: CGFloat, _ side: CGFloat) -> CGPoint {
        let radians = degrees * .pi / 180
        let along = CGVector(dx: cos(radians), dy: sin(radians))
        let across = CGVector(dx: -along.dy, dy: along.dx)
        let x = t * length
        let y = side * length * halfWidth
        return CGPoint(x: base.x + along.dx * x + across.dx * y, y: base.y + along.dy * x + across.dy * y)
    }

    /// The leaf's width at `t`, from 0 to 1, peaking about 40% of the way up.
    static func width(at t: CGFloat) -> CGFloat {
        sin(.pi * pow(min(max(t, 0), 1), 0.78))
    }

    /// The outline, with 7 teeth per edge. Each swells gently and ends in a point toward the tip.
    var path: CGPath {
        let teeth: CGFloat = 7
        let samples = 700
        func edge(_ t: CGFloat) -> CGFloat {
            // No teeth near the base or the very tip.
            let fade = min(max((t - 0.22) / 0.12, 0), 1) * min(max((0.93 - t) / 0.1, 0), 1)
            // Each tooth widens over 80% of its span, then cuts back sharply.
            let phase = (t * teeth).truncatingRemainder(dividingBy: 1)
            let notch = phase < 0.8 ? 1 - phase / 0.8 : (phase - 0.8) / 0.2
            return Leaf.width(at: t) * (1 - 0.075 * fade * notch)
        }
        let path = CGMutablePath()
        path.move(to: point(0, 0))
        for i in 0...samples {
            let t = CGFloat(i) / CGFloat(samples)
            path.addLine(to: point(t, edge(t)))
        }
        for i in stride(from: samples, through: 0, by: -1) {
            let t = CGFloat(i) / CGFloat(samples)
            path.addLine(to: point(t, -edge(t)))
        }
        path.closeSubpath()
        return path
    }
}

func drawIcon(in context: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // The tile, per the macOS icon grid: an 824-point rounded square. This fill only casts the
    // shadow; the gradient covers it.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0x000000, alpha: 0.25))
    context.addPath(tilePath)
    context.setFillColor(color(0x3B6A20))
    context.fillPath()
    context.restoreGState()

    // Top-to-bottom gradient sampled from photos of real spearmint and peppermint leaves:
    // sunlit leaf green at the top, shaded at the bottom.
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let background = CGGradient(
        colorsSpace: space,
        colors: [color(0x4D7F2F), color(0x2B5512)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    // The sprig: two leaves on short stalks and one atop the stem, all tilted 8° right.
    let node = CGPoint(x: 512, y: 380)
    let tip = CGPoint(x: 512, y: 452)
    func sideLeaf(_ degrees: CGFloat) -> Leaf {
        let radians = degrees * .pi / 180
        let base = CGPoint(x: node.x + cos(radians) * 44, y: node.y + sin(radians) * 44)
        return Leaf(base: base, degrees: degrees, length: 270)
    }
    let leaves = [sideLeaf(157), sideLeaf(23), Leaf(base: tip, degrees: 90, length: 380)]
    context.saveGState()
    context.translateBy(x: 512, y: 512)
    context.rotate(by: -8 * .pi / 180)
    context.translateBy(x: -512, y: -512)

    // One layer, so the sprig casts a single shadow and the veins can be cut through to the tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: color(0x10260A, alpha: 0.35))
    context.beginTransparencyLayer(auxiliaryInfo: nil)

    context.setStrokeColor(color(0xFFFFFF))
    context.setFillColor(color(0xFFFFFF))
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(26)
    context.move(to: CGPoint(x: 506, y: 250))
    context.addLine(to: tip)
    context.strokePath()
    context.setLineWidth(20)
    for leaf in leaves.prefix(2) {
        context.move(to: node)
        context.addLine(to: leaf.point(0.08, 0))
        context.strokePath()
    }
    for leaf in leaves {
        context.addPath(leaf.path)
        context.fillPath()
    }

    // Cut out the midrib and two pairs of side veins angled toward the tip.
    context.setBlendMode(.clear)
    context.setLineWidth(12)
    for leaf in leaves {
        context.move(to: leaf.point(0.1, 0))
        context.addLine(to: leaf.point(0.78, 0))
        context.strokePath()
        for t: CGFloat in [0.3, 0.5] {
            for side: CGFloat in [1, -1] {
                context.move(to: leaf.point(t, 0))
                context.addLine(to: leaf.point(t + 0.14, side * Leaf.width(at: t + 0.14) * 0.5))
                context.strokePath()
            }
        }
    }

    context.endTransparencyLayer()
    context.restoreGState()
    context.restoreGState()
}

// MARK: - Output

func render(pixels: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: context)
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write \(url.path)") }
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        writePNG(render(pixels: points * scale), to: outputFolder.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputFolder.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icon sizes to \(outputFolder.path)")
