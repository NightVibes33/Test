import SwiftUI

/// Background-only recreation of the approved reference: dark navy glass,
/// cyan upper arc and violet lower arc, with the original UI above it.
struct MP3SkullBackground: View {
    private let navy = Color(red: 0.018, green: 0.032, blue: 0.071)
    private let cyan = Color(red: 0.03, green: 0.79, blue: 1)
    private let blue = Color(red: 0.08, green: 0.35, blue: 0.93)
    private let violet = Color(red: 0.66, green: 0.16, blue: 1)

    var body: some View {
        Canvas { context, size in
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * size.width, y: y * size.height)
            }
            let bounds = Path(CGRect(origin: .zero, size: size))
            context.fill(bounds, with: .linearGradient(
                Gradient(colors: [navy, Color(red: 0.025, green: 0.038, blue: 0.095), navy]),
                startPoint: p(0, 0), endPoint: p(1, 1)))
            context.fill(bounds, with: .radialGradient(
                Gradient(colors: [cyan.opacity(0.25), .clear]),
                center: p(-0.06, 0.06), startRadius: 0, endRadius: size.width * 0.86))
            context.fill(bounds, with: .radialGradient(
                Gradient(colors: [violet.opacity(0.40), blue.opacity(0.09), .clear]),
                center: p(1.03, 0.88), startRadius: 0, endRadius: size.width * 0.88))
            var upper = Path()
            upper.move(to: p(-0.14, 0.45))
            upper.addCurve(to: p(1.12, 0.02), control1: p(0.28, 0.26), control2: p(0.71, 0.35))
            var glass = upper
            glass.addLine(to: p(1.12, -0.15))
            glass.addLine(to: p(-0.14, -0.15))
            glass.closeSubpath()
            context.fill(glass, with: .linearGradient(
                Gradient(colors: [cyan.opacity(0.10), blue.opacity(0.10), .clear]),
                startPoint: p(0, 0.08), endPoint: p(0.85, 0.40)))
            var lower = Path()
            lower.move(to: p(-0.15, 0.89))
            lower.addCurve(to: p(1.12, 0.60), control1: p(0.28, 0.95), control2: p(0.89, 0.82))
            var lowerGlass = lower
            lowerGlass.addLine(to: p(1.12, 1.1))
            lowerGlass.addLine(to: p(-0.15, 1.1))
            lowerGlass.closeSubpath()
            context.fill(lowerGlass, with: .linearGradient(
                Gradient(colors: [blue.opacity(0.05), violet.opacity(0.19), navy.opacity(0.2)]),
                startPoint: p(0.1, 0.82), endPoint: p(1, 0.98)))
            let topLight = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [cyan.opacity(0.95), blue.opacity(0.24), .clear]),
                startPoint: p(0, 0.40), endPoint: p(0.9, 0.15))
            let bottomLight = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [.clear, blue.opacity(0.42), violet.opacity(0.95), violet.opacity(0.22)]),
                startPoint: p(0, 0.87), endPoint: p(1.10, 0.64))
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: 19))
                glow.stroke(upper, with: topLight, lineWidth: 18)
                glow.stroke(lower, with: bottomLight, lineWidth: 23)
            }
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: 4))
                glow.stroke(upper, with: topLight, lineWidth: 5)
                glow.stroke(lower, with: bottomLight, lineWidth: 6)
            }
            context.stroke(upper, with: topLight, lineWidth: 0.9)
            context.stroke(lower, with: bottomLight, lineWidth: 1.2)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum MP3SkullTheme {
    static let card = Color(red: 0.035, green: 0.05, blue: 0.10).opacity(0.69)
}
