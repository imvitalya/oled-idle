import AppKit

// Original artwork drawn from geometry. No SF Symbols or third-party assets.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
for (points, scale) in sizes {
    let side = points * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(side) / 1024)
    transform.concat()
    let base = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 198, yRadius: 198)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0, 0, 0, 0.30)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0.06, 0.08, 0.13).setFill()
    base.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0.12, 0.18, 0.28), color(0.025, 0.04, 0.075)])!.draw(in: base, angle: -65)
    color(0.5, 0.64, 0.9, 0.20).setStroke()
    base.lineWidth = 2
    base.stroke()

    let screen = NSBezierPath(roundedRect: NSRect(x: 185, y: 315, width: 654, height: 442), xRadius: 64, yRadius: 64)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = color(0.25, 0.60, 1, 0.32)
    glow.shadowBlurRadius = 38
    glow.shadowOffset = .zero
    glow.set()
    color(0.30, 0.56, 0.88).setStroke()
    screen.lineWidth = 10
    screen.stroke()
    NSGraphicsContext.restoreGraphicsState()
    color(0.005, 0.012, 0.025).setFill()
    screen.fill()
    color(0.43, 0.69, 0.94).setStroke()
    screen.lineWidth = 8
    screen.stroke()

    let moon = NSBezierPath()
    moon.move(to: NSPoint(x: 617, y: 679))
    moon.curve(to: NSPoint(x: 449, y: 452), controlPoint1: NSPoint(x: 461, y: 727), controlPoint2: NSPoint(x: 354, y: 539))
    moon.curve(to: NSPoint(x: 653, y: 484), controlPoint1: NSPoint(x: 510, y: 397), controlPoint2: NSPoint(x: 608, y: 418))
    moon.curve(to: NSPoint(x: 520, y: 570), controlPoint1: NSPoint(x: 570, y: 453), controlPoint2: NSPoint(x: 502, y: 498))
    moon.curve(to: NSPoint(x: 617, y: 679), controlPoint1: NSPoint(x: 504, y: 633), controlPoint2: NSPoint(x: 552, y: 679))
    moon.close()
    NSGradient(colors: [color(0.50, 0.77, 1), color(0.92, 0.98, 1)])!.draw(in: moon, angle: 70)

    color(0.55, 0.73, 0.94).setFill()
    NSBezierPath(roundedRect: NSRect(x: 483, y: 256, width: 58, height: 59), xRadius: 8, yRadius: 8).fill()
    NSBezierPath(roundedRect: NSRect(x: 394, y: 236, width: 236, height: 22), xRadius: 11, yRadius: 11).fill()
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
}
