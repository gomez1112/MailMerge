import SwiftUI
import FlexStore

// MARK: - Paywall Sheet

/// Full-screen upgrade sheet presenting the Pro subscription and lifetime purchase.
/// Present this modally using `.sheet(isPresented:) { PaywallView() }`.
struct PaywallView: View {
    @Environment(StoreKitService<MailMergeTier>.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            SubscriptionShopView(
                groupID: MailMergeProductIDs.subscriptionGroupID,
                configuration: colorScheme == .dark ? .mailMergeProDark : .mailMergeProLight
            )

            // Lifetime purchase option
            lifetimeSection

            // Footer: Restore & Manage
            footerButtons
        }
        .frame(minWidth: 500, minHeight: 640)
        .background(paywallBackground)
    }

    // MARK: - Lifetime Section

    private var lifetimeSection: some View {
        VStack(spacing: 8) {
            Divider()
                .padding(.horizontal, 24)

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "infinity.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Lifetime Access")
                        .font(.system(size: 14, weight: .semibold))
                    Text("One-time purchase — Pro forever, no subscription needed.")
                        .font(.system(size: 12))
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
                .font(.system(size: 12))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .padding(.top, 8)
    }

    // MARK: - Background

    private var paywallBackground: some View {
        ZStack {
#if canImport(AppKit)
            Color(nsColor: .windowBackgroundColor)
#else
            Color(.systemBackground)
#endif
            LinearGradient(
                colors: [Color.accentColor.opacity(0.06), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Pro Badge

/// A small badge to show the user's current subscription status.
/// Use this anywhere in the UI to indicate Pro access.
struct ProBadge: View {
    @Environment(StoreKitService<MailMergeTier>.self) private var store

    var body: some View {
        if store.subscriptionTier >= .pro {
            Label("Pro", systemImage: "checkmark.seal.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
        }
    }
}

// MARK: - Upgrade Prompt Banner

/// Inline banner shown inside locked areas of the app.
/// Pass an `onUpgrade` closure to present `PaywallView`.
struct UpgradeBanner: View {
    let message: String
    let onUpgrade: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button("Upgrade") { onUpgrade() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
