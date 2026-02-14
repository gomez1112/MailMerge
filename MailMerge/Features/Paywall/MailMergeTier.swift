import FlexStore

// MARK: - Subscription Tier

/// Defines the two tiers of the Mail Merge app.
/// Free users can create jobs but are limited to 25 records per merge.
/// Pro users get unlimited records, batch PDF output, and priority support.
enum MailMergeTier: Int, SubscriptionTier, CaseIterable, Comparable {
    case free = 0
    case pro  = 1

    // MARK: SubscriptionTier

    static var defaultTier: MailMergeTier { .free }

    /// Maps the App Store Connect "level of service" integer to a tier.
    /// Set level 1 = Pro in App Store Connect.
    init?(levelOfService: Int) {
        self.init(rawValue: levelOfService)
    }

    /// Fallback initialiser for product-ID–based resolution.
    init?(productID: String) {
        switch productID {
        case MailMergeProductIDs.monthlySubscription,
             MailMergeProductIDs.annualSubscription,
             MailMergeProductIDs.lifetimePurchase:
            self = .pro
        default:
            return nil
        }
    }

    // MARK: Comparable

    static func < (lhs: MailMergeTier, rhs: MailMergeTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    // MARK: Display

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro:  return "Pro"
        }
    }
}

// MARK: - Product IDs

/// Central location for all StoreKit product identifiers.
/// Replace these with your real App Store Connect product IDs before shipping.
enum MailMergeProductIDs {
    static let monthlySubscription  = "com.mailmerge.pro.monthly"
    static let annualSubscription   = "com.mailmerge.pro.annual"
    static let lifetimePurchase     = "com.mailmerge.pro.lifetime"

    /// The subscription group ID configured in App Store Connect.
    static let subscriptionGroupID  = "MM800002"

    /// All product IDs that need to be loaded at launch.
    static let all: Set<String> = [
        monthlySubscription,
        annualSubscription,
        lifetimePurchase
    ]
}
