import AppKit
import Foundation

extension CGFloat {
    var radians: CGFloat { self * .pi / 180.0 }
}

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1.0) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }

    var cg: CGColor {
        usingColorSpace(.deviceRGB)!.cgColor
    }
}

enum Palette {
    static let midnight = NSColor(hex: 0x06111D)
    static let navy = NSColor(hex: 0x0D2035)
    static let cobalt = NSColor(hex: 0x1B6BFF)
    static let cyan = NSColor(hex: 0x63D3FF)
    static let mist = NSColor(hex: 0xEAF5FF)
    static let plateTop = NSColor(hex: 0x162738)
    static let plateBottom = NSColor(hex: 0x0B1625)
    static let plateCore = NSColor(hex: 0x13253A)
}

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appIconURL = repoRoot.appendingPathComponent("WGJ/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
let splashIconURL = repoRoot.appendingPathComponent("WGJ/Assets.xcassets/SplashIcon.imageset/SplashIcon.png")

func makeBitmap(size: Int, draw: (CGContext, CGRect) -> Void) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Unable to create bitmap representation.")
    }

    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Unable to create graphics context.")
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext

    let context = graphicsContext.cgContext
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    context.clear(rect)
    draw(context, rect)

    graphicsContext.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func savePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode PNG data.")
    }

    try data.write(to: url, options: .atomic)
}

func linearGradient(_ colors: [CGColor], locations: [CGFloat]) -> CGGradient {
    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) else {
        fatalError("Unable to create linear gradient.")
    }

    return gradient
}

func drawLinearGradient(
    in context: CGContext,
    rect: CGRect,
    colors: [CGColor],
    locations: [CGFloat],
    start: CGPoint,
    end: CGPoint
) {
    let gradient = linearGradient(colors, locations: locations)
    context.saveGState()
    context.addRect(rect)
    context.clip()
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
    context.restoreGState()
}

func drawRadialGradient(
    in context: CGContext,
    center: CGPoint,
    radius: CGFloat,
    colors: [CGColor],
    locations: [CGFloat]
) {
    let gradient = linearGradient(colors, locations: locations)
    context.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: [.drawsAfterEndLocation]
    )
}

func drawGlow(in context: CGContext, center: CGPoint, radius: CGFloat, color: NSColor, intensity: CGFloat) {
    drawRadialGradient(
        in: context,
        center: center,
        radius: radius,
        colors: [
            color.withAlphaComponent(intensity).cg,
            color.withAlphaComponent(0).cg,
        ],
        locations: [0, 1]
    )
}

func drawPlate(in context: CGContext, rect: CGRect) {
    let platePath = CGPath(ellipseIn: rect, transform: nil)
    let innerRingRect = rect.insetBy(dx: rect.width * 0.085, dy: rect.height * 0.085)
    let coreRect = rect.insetBy(dx: rect.width * 0.205, dy: rect.height * 0.205)

    context.saveGState()
    context.addPath(platePath)
    context.clip()

    drawLinearGradient(
        in: context,
        rect: rect,
        colors: [
            Palette.plateTop.cg,
            Palette.plateBottom.cg,
        ],
        locations: [0, 1],
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY)
    )

    drawGlow(
        in: context,
        center: CGPoint(x: rect.midX - rect.width * 0.22, y: rect.midY + rect.height * 0.28),
        radius: rect.width * 0.65,
        color: Palette.cyan,
        intensity: 0.10
    )

    drawGlow(
        in: context,
        center: CGPoint(x: rect.midX, y: rect.midY),
        radius: rect.width * 0.36,
        color: Palette.cobalt,
        intensity: 0.22
    )

    context.restoreGState()

    context.saveGState()
    context.setStrokeColor(Palette.mist.withAlphaComponent(0.14).cg)
    context.setLineWidth(rect.width * 0.018)
    context.addPath(platePath)
    context.strokePath()

    context.setStrokeColor(Palette.cyan.withAlphaComponent(0.16).cg)
    context.setLineWidth(rect.width * 0.012)
    context.addEllipse(in: innerRingRect)
    context.strokePath()

    context.setFillColor(Palette.plateCore.withAlphaComponent(0.82).cg)
    context.addEllipse(in: coreRect)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.setStrokeColor(Palette.mist.withAlphaComponent(0.12).cg)
    context.setLineCap(.round)
    context.setLineWidth(rect.width * 0.028)
    context.addArc(
        center: CGPoint(x: rect.midX, y: rect.midY),
        radius: rect.width * 0.43,
        startAngle: CGFloat(34.0).radians,
        endAngle: CGFloat(146.0).radians,
        clockwise: false
    )
    context.strokePath()
    context.restoreGState()
}

func markPath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let leftTop = CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.78)
    let leftValley = CGPoint(x: rect.minX + rect.width * 0.17, y: rect.minY + rect.height * 0.18)
    let centerPeak = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.60)
    let rightValley = CGPoint(x: rect.maxX - rect.width * 0.17, y: rect.minY + rect.height * 0.18)
    let rightTop = CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.78)

    path.move(to: leftTop)
    path.addLine(to: leftValley)
    path.addLine(to: centerPeak)
    path.addLine(to: rightValley)
    path.addLine(to: rightTop)
    return path
}

func drawMark(in context: CGContext, rect: CGRect) {
    let path = markPath(in: rect)

    context.saveGState()
    context.setLineCap(.round)
    context.setLineJoin(.round)

    context.setStrokeColor(Palette.cobalt.withAlphaComponent(0.28).cg)
    context.setLineWidth(rect.width * 0.24)
    context.addPath(path)
    context.strokePath()

    context.setStrokeColor(Palette.mist.cg)
    context.setLineWidth(rect.width * 0.17)
    context.addPath(path)
    context.strokePath()

    context.restoreGState()
}

func drawAppIcon(in context: CGContext, rect: CGRect) {
    drawLinearGradient(
        in: context,
        rect: rect,
        colors: [
            Palette.midnight.cg,
            Palette.navy.cg,
            Palette.cobalt.cg,
        ],
        locations: [0, 0.45, 1],
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY)
    )

    drawGlow(
        in: context,
        center: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.maxY - rect.height * 0.16),
        radius: rect.width * 0.52,
        color: Palette.cyan,
        intensity: 0.12
    )

    drawGlow(
        in: context,
        center: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.12),
        radius: rect.width * 0.54,
        color: Palette.mist,
        intensity: 0.08
    )

    let plateRect = rect.insetBy(dx: rect.width * 0.17, dy: rect.height * 0.17)
    drawPlate(in: context, rect: plateRect)

    let markRect = plateRect.insetBy(dx: plateRect.width * 0.22, dy: plateRect.height * 0.24)
    drawMark(in: context, rect: markRect)
}

func drawSplashIcon(in context: CGContext, rect: CGRect) {
    let emblemRect = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18)
    drawGlow(
        in: context,
        center: CGPoint(x: rect.midX, y: rect.midY),
        radius: rect.width * 0.28,
        color: Palette.cobalt,
        intensity: 0.12
    )

    drawPlate(in: context, rect: emblemRect)

    let markRect = emblemRect.insetBy(dx: emblemRect.width * 0.22, dy: emblemRect.height * 0.24)
    drawMark(in: context, rect: markRect)
}

let appIcon = makeBitmap(size: 1024, draw: drawAppIcon)
let splashIcon = makeBitmap(size: 1024, draw: drawSplashIcon)

do {
    try savePNG(appIcon, to: appIconURL)
    try savePNG(splashIcon, to: splashIconURL)
    print("Updated \(appIconURL.path)")
    print("Updated \(splashIconURL.path)")
} catch {
    fputs("Failed to write assets: \(error)\n", stderr)
    exit(1)
}
