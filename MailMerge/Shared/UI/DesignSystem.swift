import SwiftUI

/// Shared spacing, shapes, and motion for Mergeform's interface.
///
/// Views use these instead of literal values so the app keeps one consistent rhythm.
enum Metrics {
    /// Space between closely related items, such as an icon and its label.
    static let tight: CGFloat = 6
    /// Space between items in a group.
    static let compact: CGFloat = 10
    /// Default space between groups of content.
    static let regular: CGFloat = 16
    /// Space between major sections of a screen.
    static let section: CGFloat = 24
    /// Margin around a screen's content.
    static let page: CGFloat = 32

    /// Padding inside cards.
    static let cardPadding: CGFloat = 20
    /// Corner radius of cards and other large surfaces.
    static let cardRadius: CGFloat = 16
    /// Corner radius of tiles, rows, and controls inside cards.
    static let tileRadius: CGFloat = 10
}

/// Animations used across the app. Every view that animates goes through these so motion
/// feels consistent and Reduce Motion is honored in one place.
enum Motion {
    /// Layout and content changes.
    static let standard = Animation.smooth(duration: 0.35)
    /// Selection and hover feedback, which should feel immediate.
    static let quick = Animation.snappy(duration: 0.22)
    /// Moments worth celebrating, such as completing a step.
    static let lively = Animation.bouncy(duration: 0.45, extraBounce: 0.05)

    /// `animation`, or a short cross-fade when Reduce Motion is on.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : animation
    }
}

// MARK: - Card Surface

private struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let padding: CGFloat?
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.mergeformPanel)
                    // A soft lift reads well on light backgrounds; in Dark Mode the panel's
                    // lighter tone already separates it.
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 12, y: 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.mergeformStroke)
            }
    }
}

// MARK: - Reveal on Appear

private struct RevealOnAppear: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let order: Int
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 12)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.98, anchor: .top)
            .onAppear {
                guard !isVisible else { return }
                // Later items start slightly later, capped so long lists don't lag.
                let delay = reduceMotion ? 0 : min(Double(order), 8) * 0.04
                withAnimation(Motion.resolved(Motion.standard, reduceMotion: reduceMotion).delay(delay)) {
                    isVisible = true
                }
            }
    }
}

// MARK: - Hover Lift

private struct HoverLift: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering && !reduceMotion ? 1.012 : 1)
            .shadow(
                color: .black.opacity(isHovering ? (colorScheme == .dark ? 0.35 : 0.10) : 0),
                radius: isHovering ? 16 : 0,
                y: isHovering ? 6 : 0
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.mergeformBlue.opacity(isHovering ? 0.35 : 0))
            }
            .onHover { isHovering = $0 }
            .animation(Motion.resolved(Motion.quick, reduceMotion: reduceMotion), value: isHovering)
    }
}

extension View {
    /// Places the view on a card: the panel fill, a hairline border, and a soft shadow.
    func cardSurface(padding: CGFloat? = Metrics.cardPadding, radius: CGFloat = Metrics.cardRadius) -> some View {
        modifier(CardSurface(padding: padding, radius: radius))
    }

    /// Fades and rises the view into place the first time it appears. `order` staggers
    /// items in a group. With Reduce Motion on, the view only fades in.
    func revealOnAppear(order: Int = 0) -> some View {
        modifier(RevealOnAppear(order: order))
    }

    /// Lifts the view slightly and outlines it while the pointer is over it.
    func hoverLift(radius: CGFloat = Metrics.cardRadius) -> some View {
        modifier(HoverLift(radius: radius))
    }

    /// Animates changes to `value` with `animation`, or a short cross-fade when Reduce
    /// Motion is on.
    func motion<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(MotionAnimation(animation: animation, value: value))
    }
}

private struct MotionAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(Motion.resolved(animation, reduceMotion: reduceMotion), value: value)
    }
}

// MARK: - Icon Tile

/// A symbol on a tinted rounded square, used to label files, stats, and sections.
struct IconTile: View {
    let systemImage: String
    var tint: Color = .mergeformBlue
    var size: CGFloat = 40
    /// A filled tile with a white symbol, for the most prominent icons.
    var isProminent = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(isProminent ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(isProminent ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.13)))
            }
            .accessibilityHidden(true)
    }
}
