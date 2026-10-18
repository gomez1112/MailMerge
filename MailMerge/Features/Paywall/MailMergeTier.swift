import FlexStore

// MARK: - Subscription Tier

/// Defines the two tiers of the Mergeform app.
/// Every feature is available on both. The free plan includes a limited number of jobs
/// in total (see `JobAllowance`); Pro, by subscription or lifetime purchase, removes the
/// limit.
enum MailMergeTier: Int, SubscriptionTier, CaseIterable, Comparable {
    case free = 0
    case pro  = 1

    // MARK: SubscriptionTier

    static var defaultTier: MailMergeTier { .free }

    /// Maps the App Store Connect "level of service" integer to a tier.
    /// Set level 1 = Pro in App Store Connect.
    init?(levelOfService: Int) {
        switch levelOfService {
        case ..<0:
            return nil
        case 0:
            self = .free
        default:
            self = .pro
        }
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

// MARK: - Pro Access

extension MailMergeTier {
    /// Whether the user's purchases unlock Pro: an active subscription, or the lifetime
    /// purchase, which isn't part of the subscription group's tier.
    static func hasProAccess(subscriptionTier: MailMergeTier, purchasedProductIDs: Set<String>) -> Bool {
        subscriptionTier >= .pro || purchasedProductIDs.contains(MailMergeProductIDs.lifetimePurchase)
    }
}

extension StoreKitService where Tier == MailMergeTier {
    /// Whether the user has Pro, from a subscription or the lifetime purchase.
    var hasProAccess: Bool {
        MailMergeTier.hasProAccess(subscriptionTier: subscriptionTier, purchasedProductIDs: purchasedNonConsumables)
    }
}

/// The free plan's job allowance: a number of jobs in total. Deleting a job doesn't give
/// one back.
enum JobAllowance {
    static let freeJobLimit = 3

    static let limitReachedMessage = "The free plan includes \(freeJobLimit) jobs in total, and deleting a job doesn't free up a slot. Upgrade to Pro or Lifetime for unlimited jobs."
}

// MARK: - Product IDs

/// Central location for all StoreKit product identifiers.
/// Replace these with your real App Store Connect product IDs before shipping.
nonisolated enum MailMergeProductIDs {
    static let monthlySubscription  = "com.mergeform.pro.monthly"
    static let annualSubscription   = "com.mergeform.pro.annual"
    static let lifetimePurchase     = "com.mergeform.pro.lifetime"

    /// The subscription group ID configured in App Store Connect.
    static let subscriptionGroupID  = "21934274"

    /// All product IDs that need to be loaded at launch.
    static let all: Set<String> = [
        monthlySubscription,
        annualSubscription,
        lifetimePurchase
    ]
}
