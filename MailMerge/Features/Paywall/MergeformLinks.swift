import Foundation

/// Mergeform's legal pages, shown in Settings and in the paywall as App Review requires
/// for auto-renewable subscriptions.
enum MergeformLinks {
    // These are fixed, well-formed URLs, so creating them can't fail.
    static let privacyPolicy = URL(string: "https://transfinite.us/policies/MergeformPrivacy/")!
    static let termsOfUse = URL(string: "https://transfinite.us/policies/MergeformTerms/")!
}
