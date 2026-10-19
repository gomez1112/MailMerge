import SwiftUI
import OnboardingKit

// MARK: - Onboarding Pages

extension OnboardingPage {
    static var mailMergePages: [OnboardingPage] {
        [
            OnboardingPage(
                title: "Welcome to Mergeform",
                description: "Turn any DOCX template and Excel spreadsheet into a batch of personalized PDF documents — in seconds.",
                systemImage: "document.on.document.fill",
                backgroundColor: .clear,
                iconColor: .mergeformBlue
            ),
            OnboardingPage(
                title: "Start with a Template",
                description: "Pick any DOCX file as your template. Mergeform automatically detects your merge fields — supports {{Field}}, <<Field>>, ${Field}, and [[Field]] formats.",
                systemImage: "richtext.page.fill",
                backgroundColor: .clear,
                iconColor: .mergeformBlue
            ),
            OnboardingPage(
                title: "Connect Your Data",
                description: "Import an Excel spreadsheet and choose the sheet to use. Mergeform reads your column headers and shows you a live data preview.",
                systemImage: "tablecells.fill",
                backgroundColor: .clear,
                iconColor: .green
            ),
            OnboardingPage(
                title: "Map Fields Automatically",
                description: "Fields are matched to your spreadsheet columns intelligently. Fine-tune mappings manually, and apply transformations like Title Case, Currency, or Date Format.",
                systemImage: "arrow.left.arrow.right",
                backgroundColor: .clear,
                iconColor: .purple
            ),
            OnboardingPage(
                title: "Preview Before You Merge",
                description: "Step through individual records and see a live PDF preview before running the full merge. When you're ready, Mergeform generates all your documents at once.",
                systemImage: "play.rectangle.fill",
                backgroundColor: .clear,
                iconColor: .green
            ),
        ]
    }
}

// MARK: - What's New Feature Items

extension FeatureItem {
    /// The highlights of the current version, shown once to people who update.
    /// Update these with each release.
    static var mailMergeFeatures: [FeatureItem] {
        [
            FeatureItem(
                title: "Suggest Features",
                description: "Choose Feature Requests in the sidebar to share an idea, vote for the ones you want most, and see what’s planned.",
                systemImage: "lightbulb.fill",
                iconColor: .mergeformOrange
            ),
            FeatureItem(
                title: "Reliable Pro Purchases",
                description: "Pro unlocks immediately after purchase, with clearer errors and a lifetime purchase option that can retry if you were offline.",
                systemImage: "checkmark.circle.fill",
                iconColor: .mergeformBlue
            ),
            FeatureItem(
                title: "More Accurate Excel Formatting",
                description: "Keep phone and ZIP+4 punctuation, original dates, accounting values, and consistent rounding in your documents.",
                systemImage: "tablecells.fill",
                iconColor: .green
            ),
            FeatureItem(
                title: "Your Documents Stay Separate",
                description: "Each merge keeps its own email attachment. Existing PDFs are preserved, and new files get a numbered name.",
                systemImage: "folder.fill",
                iconColor: .mergeformOrange
            ),
            FeatureItem(
                title: "Smoother Job Setup",
                description: "Templates are scanned when you start a job. Column lists update as they load, and switching sheets preserves your manual mappings.",
                systemImage: "arrow.left.arrow.right",
                iconColor: .purple
            ),
        ]
    }
}
