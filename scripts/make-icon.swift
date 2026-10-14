// Renders the ImgCast app icon to a 1024x1024 PNG.
// usage: swift scripts/make-icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let out = URL(fileURLWithPath: CommandLine.arguments[1])

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS-style rounded square with an indigo -> teal gradient
    let inset: CGFloat = 100
    let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    ctx.addPath(path)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [NSColor(srgbRed: 0.33, green: 0.30, blue: 0.95, alpha: 1).cgColor,
                                       NSColor(srgbRed: 0.10, green: 0.75, blue: 0.80, alpha: 1).cgColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY), options: [])
    ctx.restoreGState()

    // two stacked "photo" cards with a conversion arrow
    func card(_ rect: CGRect, alpha: CGFloat) {
        let card = CGPath(roundedRect: rect, cornerWidth: 40, cornerHeight: 40, transform: nil)
        ctx.addPath(card)
        ctx.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
        ctx.fillPath()
        // mountain + sun
        ctx.setFillColor(NSColor(srgbRed: 0.33, green: 0.30, blue: 0.95, alpha: alpha).cgColor)
        let m = CGMutablePath()
        m.move(to: CGPoint(x: rect.minX + 40, y: rect.minY + 40))
        m.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.62))
        m.addLine(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.38))
        m.addLine(to: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.minY + rect.height * 0.5))
        m.addLine(to: CGPoint(x: rect.maxX - 40, y: rect.minY + 40))
        m.closeSubpath()
        ctx.addPath(m)
        ctx.fillPath()
        ctx.fillEllipse(in: CGRect(x: rect.maxX - rect.width * 0.32, y: rect.maxY - rect.height * 0.36,
                                   width: rect.width * 0.16, height: rect.width * 0.16))
    }
    card(CGRect(x: 230, y: 400, width: 380, height: 320), alpha: 0.55)
    card(CGRect(x: 414, y: 300, width: 380, height: 320), alpha: 1)

    // arrow
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(34)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: 300, y: 300))
    ctx.addQuadCurve(to: CGPoint(x: 380, y: 210), control: CGPoint(x: 300, y: 210))
    ctx.strokePath()
    ctx.move(to: CGPoint(x: 340, y: 250))
    ctx.addLine(to: CGPoint(x: 385, y: 210))
    ctx.addLine(to: CGPoint(x: 340, y: 170))
    ctx.strokePath()
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
