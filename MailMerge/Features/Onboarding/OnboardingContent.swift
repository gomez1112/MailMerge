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
    static var mailMergeFeatures: [FeatureItem] {
        [
            FeatureItem(
                title: "Template Library",
                description: "Browse and reuse all your DOCX templates from one place. Import a new template or start a job directly from the library.",
                systemImage: "richtext.page.fill",
                iconColor: .mergeformBlue
            ),
            FeatureItem(
                title: "Smart Field Matching",
                description: "Fields are automatically paired with spreadsheet columns using intelligent fuzzy matching, saving you time on every job.",
                systemImage: "wand.and.sparkles",
                iconColor: .purple
            ),
            FeatureItem(
                title: "Field Transformations",
                description: "Apply formatting rules per field — uppercase, title case, date format, currency, and more — right inside the mapping step.",
                systemImage: "arrow.left.arrow.right",
                iconColor: .purple
            ),
            FeatureItem(
                title: "Flexible Output Patterns",
                description: "Name your output files dynamically using column values like {FirstName}_{LastName}.pdf. Preview the result before merging.",
                systemImage: "folder.badge.gearshape",
                iconColor: .mergeformOrange
            ),
        ]
    }
}
