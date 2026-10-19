import StoreKit
import SwiftUI

// MARK: - Paywall Sheet

/// The upgrade sheet presenting the Pro subscriptions and the lifetime purchase.
/// Present it modally using `.sheet(isPresented:) { PaywallView() }`.
struct PaywallView: View {
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isBuyingLifetime = false
    @State private var purchaseErrorMessage = ""
    @State private var showingPurchaseError = false

    var body: some View {
        VStack(spacing: 0) {
            SubscriptionStoreView(groupID: MailMergeProductIDs.subscriptionGroupID) {
                ProOfferHeader()
            }
            .storeButton(.visible, for: .restorePurchases)
            .subscriptionStorePolicyDestination(url: MergeformLinks.termsOfUse, for: .termsOfService)
            .subscriptionStorePolicyDestination(url: MergeformLinks.privacyPolicy, for: .privacyPolicy)
            .onInAppPurchaseCompletion { _, result in
                do {
                    if try await purchases.completePurchase(result.get()) { dismiss() }
                } catch {
                    purchaseErrorMessage = error.localizedDescription
                    showingPurchaseError = true
                }
            }

            lifetimeSection

            footer
        }
        .frame(minWidth: 520, minHeight: 680)
        .onChange(of: purchases.hasProAccess) { _, hasPro in
            if hasPro { dismiss() }
        }
        .task {
            // Show the price, and retry a load that failed at launch.
            _ = try? await purchases.loadLifetimeProduct()
        }
        .alert("Purchase Failed", isPresented: $showingPurchaseError) {
            Button("OK") { }
        } message: {
            Text(purchaseErrorMessage)
        }
    }

    private func buyLifetime() {
        isBuyingLifetime = true
        Task {
            defer { isBuyingLifetime = false }
            do {
                _ = try await purchases.purchaseLifetime()
            } catch {
                purchaseErrorMessage = error.localizedDescription
                showingPurchaseError = true
            }
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

                Button(action: buyLifetime) {
                    if purchases.ownsLifetime {
                        Text("Purchased")
                    } else if isBuyingLifetime {
                        Text("Buying…")
                    } else {
                        Text(purchases.lifetimeProduct.map { "Buy for \($0.displayPrice)" } ?? "Buy")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(purchases.ownsLifetime || isBuyingLifetime)
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

            Button("Manage Subscriptions") {
                openURL(MergeformLinks.manageSubscriptions)
            }
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
