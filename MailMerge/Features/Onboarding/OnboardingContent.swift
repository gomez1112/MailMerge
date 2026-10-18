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
                title: "A Fresh New Look",
                description: "A redesigned Mac app with a native sidebar, full Dark Mode support, and smooth animations that follow your Reduce Motion setting.",
                systemImage: "sparkles",
                iconColor: .mergeformBlue
            ),
            FeatureItem(
                title: "Find Your PDFs Instantly",
                description: "After a merge, see which folder your PDFs were saved in and open it in Finder with the new files selected.",
                systemImage: "folder.fill",
                iconColor: .mergeformOrange
            ),
            FeatureItem(
                title: "Spreadsheets Exactly as in Excel",
                description: "Dates, percentages, ZIP codes with leading zeros, formulas, and rich text now come through just as Excel shows them.",
                systemImage: "tablecells.fill",
                iconColor: .green
            ),
            FeatureItem(
                title: "Drag and Drop",
                description: "Drop a template, spreadsheet, or output folder right onto its step. Jobs keep working when you move or rename their files.",
                systemImage: "tray.and.arrow.down.fill",
                iconColor: .mergeformBlue
            ),
            FeatureItem(
                title: "Stay in Control of Merges",
                description: "Cancel a merge at any time. Its progress stays put while you move between steps.",
                systemImage: "stop.circle.fill",
                iconColor: .purple
            ),
        ]
    }
}
