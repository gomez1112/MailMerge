import SwiftUI
import FlexStore

// MARK: - Paywall Features

extension FlexPaywallFeature {
    /// Features highlighted in the Pro upgrade paywall.
    static var mailMergeProFeatures: [FlexPaywallFeature] {
        [
            FlexPaywallFeature(
                systemImage: "infinity",
                title: "Unlimited Records",
                subtitle: "Merge thousands of rows in a single run — no caps, no limits.",
                tint: .accentColor
            ),
            FlexPaywallFeature(
                systemImage: "doc.on.doc.fill",
                title: "Batch PDF Output",
                subtitle: "Generate every record as its own PDF or combine them all into one document.",
                tint: .purple
            ),
            FlexPaywallFeature(
                systemImage: "wand.and.stars",
                title: "Smart Field Matching",
                subtitle: "Auto-map template placeholders to spreadsheet columns using fuzzy matching.",
                tint: .orange
            ),
            FlexPaywallFeature(
                systemImage: "arrow.left.arrow.right",
                title: "Field Transformations",
                subtitle: "Format values as Title Case, Currency, Date, and more — per field.",
                tint: .green
            ),
            FlexPaywallFeature(
                systemImage: "folder.badge.gearshape",
                title: "Custom Output Patterns",
                subtitle: "Name your output files dynamically using column values from your data.",
                tint: .blue
            ),
        ]
    }
}

// MARK: - Shop Configuration

extension SubscriptionShopConfiguration {
    /// Configuration used by the SubscriptionShopView paywall sheet.
    static var mailMergePro: SubscriptionShopConfiguration {
        mailMergeProDark
    }

    static var mailMergeProDark: SubscriptionShopConfiguration {
        SubscriptionShopConfiguration(
            title: "Mergeform Pro",
            subtitle: "Automate documents without limits",
            heroSystemImage: "doc.on.doc.fill",
            features: [
                SubscriptionFeature(
                    icon: "infinity",
                    title: "Unlimited Records",
                    description: "Merge as many rows as your spreadsheet has.",
                    accentColor: .accentColor
                ),
                SubscriptionFeature(
                    icon: "doc.on.doc.fill",
                    title: "Batch PDF Output",
                    description: "Individual files or a single combined PDF.",
                    accentColor: .purple
                ),
                SubscriptionFeature(
                    icon: "wand.and.stars",
                    title: "Smart Field Matching",
                    description: "Automatic placeholder-to-column mapping.",
                    accentColor: .orange
                ),
                SubscriptionFeature(
                    icon: "arrow.left.arrow.right",
                    title: "Field Transformations",
                    description: "Date, currency, case formatting per field.",
                    accentColor: .green
                ),
                SubscriptionFeature(
                    icon: "folder.badge.gearshape",
                    title: "Custom Output Patterns",
                    description: "Dynamic file names from your data columns.",
                    accentColor: .blue
                ),
            ],
            tiers: [
                AppSubscriptionTier(
                    productID: MailMergeProductIDs.monthlySubscription,
                    systemImage: "calendar",
                    color: .accentColor
                ),
                AppSubscriptionTier(
                    productID: MailMergeProductIDs.annualSubscription,
                    systemImage: "calendar.badge.checkmark",
                    color: .purple
                ),
            ],
            theme: .custom(
                colors: [
                    Color(red: 0.12, green: 0.08, blue: 0.06),
                    Color(red: 0.18, green: 0.11, blue: 0.07),
                    Color(red: 0.10, green: 0.07, blue: 0.05)
                ],
                accent: .accentColor,
                titleColor: .white,
                subtitleColor: .white.opacity(0.9),
                cardStyle: .elevated,
                heroStyle: .simple
            ),
            pickerBackground: Material.ultraThickMaterial
        )
    }

    static var mailMergeProLight: SubscriptionShopConfiguration {
        SubscriptionShopConfiguration(
            title: "Mergeform",
            subtitle: "Automate documents without limits",
            heroSystemImage: "doc.on.doc.fill",
            features: [
                SubscriptionFeature(
                    icon: "infinity",
                    title: "Unlimited Records",
                    description: "Merge as many rows as your spreadsheet has.",
                    accentColor: .accentColor
                ),
                SubscriptionFeature(
                    icon: "doc.on.doc.fill",
                    title: "Batch PDF Output",
                    description: "Individual files or a single combined PDF.",
                    accentColor: .purple
                ),
                SubscriptionFeature(
                    icon: "wand.and.stars",
                    title: "Smart Field Matching",
                    description: "Automatic placeholder-to-column mapping.",
                    accentColor: .orange
                ),
                SubscriptionFeature(
                    icon: "arrow.left.arrow.right",
                    title: "Field Transformations",
                    description: "Date, currency, case formatting per field.",
                    accentColor: .green
                ),
                SubscriptionFeature(
                    icon: "folder.badge.gearshape",
                    title: "Custom Output Patterns",
                    description: "Dynamic file names from your data columns.",
                    accentColor: .blue
                ),
            ],
            tiers: [
                AppSubscriptionTier(
                    productID: MailMergeProductIDs.monthlySubscription,
                    systemImage: "calendar",
                    color: .accentColor
                ),
                AppSubscriptionTier(
                    productID: MailMergeProductIDs.annualSubscription,
                    systemImage: "calendar.badge.checkmark",
                    color: .purple
                ),
            ],
            theme: .custom(
                colors: [
                    Color(red: 0.98, green: 0.96, blue: 0.94),
                    Color(red: 0.96, green: 0.94, blue: 0.92),
                    Color(red: 0.99, green: 0.98, blue: 0.97)
                ],
                accent: .accentColor,
                titleColor: .black,
                subtitleColor: .black.opacity(0.7),
                cardStyle: .elevated,
                heroStyle: .simple
            ),
            pickerBackground: Material.regularMaterial
        )
    }
}
