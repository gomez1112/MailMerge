import Foundation

/// Mergeform's legal pages, shown in Settings and in the paywall as App Review requires
/// for auto-renewable subscriptions, and the App Store's subscription management page.
enum MergeformLinks {
    // These are fixed, well-formed URLs, so creating them can't fail.
    static let privacyPolicy = URL(string: "https://transfinite.us/policies/MergeformPrivacy/")!
    static let termsOfUse = URL(string: "https://transfinite.us/policies/MergeformTerms/")!
    /// The App Store's subscription management page, which opens in the App Store app.
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
}
