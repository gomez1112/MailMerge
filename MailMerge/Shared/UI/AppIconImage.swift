import AppKit
import SwiftUI

/// Mergeform's app icon, exactly as the Dock and Finder show it, for places that stand
/// for the app itself, such as the sidebar header and the paywall.
///
/// SwiftUI can't load an app icon, so this asks AppKit for the icon the system renders
/// from MergeformIcon.icon. Changing that icon updates every place that shows this view.
struct AppIconImage: View {
    /// The width and height of the icon's rounded square.
    var size: CGFloat

    /// The rounded square fills 824 of the 1024 points of a macOS icon; the rest is a
    /// transparent margin that holds the icon's shadow.
    private static let artworkFraction: CGFloat = 824 / 1024

    var body: some View {
        let canvasSize = size / Self.artworkFraction
        Group {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                IconTile(systemImage: "document.on.document.fill", size: size, isProminent: true)
            }
        }
        // The margin overflows the frame, so the rounded square lines up with nearby
        // content instead of looking inset.
        .frame(width: canvasSize, height: canvasSize)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
