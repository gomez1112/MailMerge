import FlexStore
import StoreKit
import SwiftUI

// MARK: - Paywall Sheet

/// The upgrade sheet presenting the Pro subscriptions and the lifetime purchase.
/// Present it modally using `.sheet(isPresented:) { PaywallView() }`.
struct PaywallView: View {
    @Environment(StoreKitService<MailMergeTier>.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SubscriptionStoreView(groupID: MailMergeProductIDs.subscriptionGroupID) {
                ProOfferHeader()
            }
            .storeButton(.visible, for: .restorePurchases)
            .subscriptionStorePolicyDestination(url: MergeformLinks.termsOfUse, for: .termsOfService)
            .subscriptionStorePolicyDestination(url: MergeformLinks.privacyPolicy, for: .privacyPolicy)
            .onInAppPurchaseCompletion { _, result in
                // Close only when a purchase goes through. Cancelling, a pending (Ask to
                // Buy) purchase, or an error leaves the paywall open.
                if case .success(.success) = result {
                    dismiss()
                }
            }

            lifetimeSection

            footer
        }
        .frame(minWidth: 520, minHeight: 680)
        .onChange(of: store.hasProAccess) { _, hasPro in
            if hasPro { dismiss() }
        }
    }

    // MARK: - Lifetime Section

    private var lifetimeSection: some View {
        VStack(spacing: 8) {
            Divider()

            HStack(spacing: 12) {
                IconTile(systemImage: "infinity", tint: .mergeformOrange, size: 44, isProminent: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Lifetime Access")
                        .font(.headline)
                    Text("One-time purchase — Pro forever, no subscription needed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                NonConsumablePurchaseButton<MailMergeTier>(
                    productID: MailMergeProductIDs.lifetimePurchase,
                    title: "Buy",
                    purchasedTitle: "Purchased"
                )
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 16) {
            Link("Terms of Use", destination: MergeformLinks.termsOfUse)
            Link("Privacy Policy", destination: MergeformLinks.privacyPolicy)

            Spacer()

            ManageSubscriptionsButton()
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button("Not Now") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .font(.callout)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .padding(.top, 8)
    }
}

// MARK: - Offer Header

/// The marketing content above the subscription options.
private struct ProOfferHeader: View {
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                AppIconImage(size: 72)
                    .padding(.bottom, 4)
                Text(MergeformProOffer.headline)
                    .font(.title)
                    .bold()
                Text(MergeformProOffer.subheadline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(MergeformProOffer.features) { feature in
                    HStack(alignment: .top, spacing: 12) {
                        IconTile(systemImage: feature.systemImage, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                                .font(.headline)
                            Text(feature.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: 420, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }
}
