import SwiftUI

/// Dedicated seasonal materials, independent of the selected palette so previews
/// show the actual Christmas design before it is enabled.
enum WGJChristmasStyle {
    static let cranberry = Color(UIColor(hex: 0xA51B31))
    static let deepRed = Color(UIColor(hex: 0x731425))
    static let cream = Color(UIColor(hex: 0xFFF5DD))
    static let gold = Color(UIColor(hex: 0xF3CA6C))
    static let pine = Color(UIColor(hex: 0x23613B))
    static let pineLight = Color(UIColor(hex: 0x3B8750))
    static var ribbonGradient: LinearGradient {
        LinearGradient(colors: [cranberry, deepRed], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct WGJChristmasCandyStripe: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(WGJChristmasStyle.cream))
            for x in stride(from: -12.0, to: size.width + 12, by: 16) {
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: size.height))
                stripe.addLine(to: CGPoint(x: x + 6, y: 0))
                stripe.addLine(to: CGPoint(x: x + 13, y: 0))
                stripe.addLine(to: CGPoint(x: x + 7, y: size.height))
                stripe.closeSubpath()
                context.fill(stripe, with: .color(WGJChristmasStyle.cranberry))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Vector artwork scales sharply on phones and iPad, without image downloads.
struct WGJChristmasTreeArtwork: View {
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 140, y: size.height / 180)
            context.fill(Path(ellipseIn: CGRect(x: 6, y: 159, width: 128, height: 13)),
                         with: .color(WGJChristmasStyle.cream.opacity(0.18)))
            context.fill(Path(CGRect(x: 66, y: 133, width: 9, height: 30)), with: .color(WGJChristmasStyle.gold))
            for tier in 0..<4 {
                let top = CGFloat(20 + tier * 26)
                let half = CGFloat(23 + tier * 9)
                var bough = Path()
                bough.move(to: CGPoint(x: 70, y: top))
                bough.addQuadCurve(to: CGPoint(x: 70 + half, y: top + 49), control: CGPoint(x: 75 + half / 2, y: top + 33))
                bough.addQuadCurve(to: CGPoint(x: 70 - half, y: top + 49), control: CGPoint(x: 70, y: top + 61))
                bough.addQuadCurve(to: CGPoint(x: 70, y: top), control: CGPoint(x: 65 - half / 2, y: top + 33))
                context.fill(bough, with: .color(tier.isMultiple(of: 2) ? WGJChristmasStyle.pineLight : WGJChristmasStyle.pine))
                var snow = Path()
                snow.move(to: CGPoint(x: 70 - half + 4, y: top + 48))
                snow.addQuadCurve(to: CGPoint(x: 70 + half - 4, y: top + 48), control: CGPoint(x: 70, y: top + 59))
                context.stroke(snow, with: .color(WGJChristmasStyle.cream.opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            let ornaments: [CGPoint] = [.init(x: 68, y: 45), .init(x: 55, y: 69), .init(x: 82, y: 77),
                .init(x: 49, y: 98), .init(x: 74, y: 102), .init(x: 91, y: 119), .init(x: 38, y: 131), .init(x: 66, y: 138)]
            for (index, point) in ornaments.enumerated() {
                let color = index.isMultiple(of: 2) ? WGJChristmasStyle.gold : Color(UIColor(hex: 0xF64B57))
                context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(color))
            }
            var star = context.resolve(Image(systemName: "star.fill"))
            star.shading = .color(WGJChristmasStyle.gold)
            context.draw(star, in: CGRect(x: 60, y: 9, width: 20, height: 20))
            for (index, rect) in [CGRect(x: 18, y: 147, width: 30, height: 24), CGRect(x: 94, y: 144, width: 29, height: 27)].enumerated() {
                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(index == 0 ? WGJChristmasStyle.cranberry : WGJChristmasStyle.cream))
                context.fill(Path(CGRect(x: rect.midX - 2, y: rect.minY, width: 4, height: rect.height)), with: .color(WGJChristmasStyle.gold))
                context.fill(Path(CGRect(x: rect.minX, y: rect.minY + 7, width: rect.width, height: 3)), with: .color(WGJChristmasStyle.gold))
                var bow = context.resolve(Image(systemName: "gift.fill"))
                bow.shading = .color(WGJChristmasStyle.gold)
                context.draw(bow, in: CGRect(x: rect.midX - 8, y: rect.minY - 10, width: 16, height: 14))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
