/// Mergeform's App Store product identifiers.
nonisolated enum MailMergeProductIDs {
    static let monthlySubscription = "com.mergeform.pro.monthly"
    static let annualSubscription = "com.mergeform.pro.annual"
    static let lifetimePurchase = "com.mergeform.pro.lifetime"

    /// The subscription group in App Store Connect.
    static let subscriptionGroupID = "21934274"

    static let subscriptions: Set<String> = [monthlySubscription, annualSubscription]
}
