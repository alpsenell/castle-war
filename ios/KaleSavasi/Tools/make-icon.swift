// Draws the app icon. Run: swift Tools/make-icon.swift Sources/Assets.xcassets/AppIcon.appiconset/icon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func col(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}
let ink = col(0x1b2a34)
func block(_ r: CGRect, _ hex: UInt32, line: CGFloat = 14) {
    ctx.setFillColor(col(hex)); ctx.fill(r)
    ctx.setStrokeColor(ink); ctx.setLineWidth(line); ctx.setLineJoin(.round); ctx.stroke(r)
}
func roof(_ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat, _ h: CGFloat) {
    ctx.beginPath(); ctx.move(to: CGPoint(x: x0 - 22, y: y)); ctx.addLine(to: CGPoint(x: x1 + 22, y: y)); ctx.addLine(to: CGPoint(x: (x0 + x1) / 2, y: y + h)); ctx.closePath()
    ctx.setFillColor(col(0xc62d1f)); ctx.setStrokeColor(ink); ctx.setLineWidth(14); ctx.setLineJoin(.round); ctx.drawPath(using: .fillStroke)
}
// sky and grass
let sky = CGGradient(colorsSpace: nil, colors: [col(0x3b8fe0), col(0xbfe6ff)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 240), options: [.drawsAfterEndLocation])
ctx.setFillColor(col(0x5aa846)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: 250))
// curtain wall with battlements and a gate
block(CGRect(x: 300, y: 200, width: 424, height: 300), 0xb4b9be)
for i in 0..<4 { block(CGRect(x: 318 + CGFloat(i) * 104, y: 500, width: 64, height: 60), 0xc3c7cb) }
block(CGRect(x: 300, y: 436, width: 424, height: 34), 0xc62d1f, line: 10)
ctx.setFillColor(ink)
ctx.addPath(CGPath(roundedRect: CGRect(x: 452, y: 193, width: 120, height: 170), cornerWidth: 60, cornerHeight: 60, transform: nil)); ctx.fillPath()
ctx.fill(CGRect(x: 452, y: 193, width: 120, height: 80))
// towers
for x in [CGFloat(170), 654] {
    block(CGRect(x: x, y: 200, width: 200, height: 470), 0xa5abb1)
    block(CGRect(x: x, y: 420, width: 200, height: 36), 0x70767c, line: 10)
    for i in 0..<3 { block(CGRect(x: x + 6 + CGFloat(i) * 68, y: 670, width: 52, height: 56), 0xc3c7cb) }
    roof(x + 30, x + 170, 726, 150)
    ctx.setFillColor(ink); ctx.fill(CGRect(x: x + 86, y: 520, width: 28, height: 90))
}
// cannonball with a streak, and a loose block
ctx.setStrokeColor(col(0xffffff)); ctx.setLineWidth(26); ctx.setLineCap(.round)
ctx.beginPath(); ctx.move(to: CGPoint(x: 120, y: 930)); ctx.addQuadCurve(to: CGPoint(x: 470, y: 800), control: CGPoint(x: 330, y: 960)); ctx.strokePath()
ctx.setFillColor(ink); ctx.fillEllipse(in: CGRect(x: 440, y: 720, width: 130, height: 130))
ctx.saveGState(); ctx.translateBy(x: 590, y: 640); ctx.rotate(by: 0.5); block(CGRect(x: -40, y: -26, width: 80, height: 52), 0xc3c7cb, line: 10); ctx.restoreGState()

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
