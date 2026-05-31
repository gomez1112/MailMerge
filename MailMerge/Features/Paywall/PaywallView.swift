import SwiftUI
import FlexStore
import AppKit

// MARK: - Paywall Sheet

/// Full-screen upgrade sheet presenting the Pro subscription and lifetime purchase.
/// Present this modally using `.sheet(isPresented:) { PaywallView() }`.
struct PaywallView: View {
    @Environment(StoreKitService<MailMergeTier>.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            paywallHeader

            SubscriptionShopView(
                groupID: MailMergeProductIDs.subscriptionGroupID,
                configuration: colorScheme == .dark ? .mailMergeProDark : .mailMergeProLight
            )

            lifetimeSection

            footerButtons
        }
        .frame(minWidth: 500, minHeight: 640)
        .background(paywallBackground)
    }

    private var paywallHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "bolt.doc.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.mergeformBlue, in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text("Mergeform Pro")
                    .font(.title2)
                    .bold()
                    .foregroundStyle(Color.mergeformInk)
                Text("Higher limits, faster document runs, and advanced output workflows.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(24)
        .background(Color.mergeformPanel)
    }

    // MARK: - Lifetime Section

    private var lifetimeSection: some View {
        VStack(spacing: 8) {
            Divider()
                .padding(.horizontal, 24)

            HStack(spacing: 12) {
                Image(systemName: "infinity.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.mergeformOrange, in: .rect(cornerRadius: 10))

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

    // MARK: - Footer Buttons

    private var footerButtons: some View {
        HStack(spacing: 16) {
            RestorePurchasesButton<MailMergeTier>()
                .buttonStyle(.bordered)
                .controlSize(.small)

            ManageSubscriptionsButton()
                .buttonStyle(.bordered)
                .controlSize(.small)

            Spacer()

            Button("No thanks") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .padding(.top, 8)
    }

    // MARK: - Background

    private var paywallBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Color.mergeformBackground.opacity(0.65)
        }
        .ignoresSafeArea()
    }
}
