# Mergeform — Mail Merge for iOS & macOS

Mergeform is a document automation app that lets you combine DOCX templates with Excel data sources to generate personalized PDFs in bulk. Built with SwiftUI and SwiftData, it runs natively on iPhone, iPad, and Mac.

---

## Features

### Core Merge
- Import `.docx` templates with placeholder fields in multiple formats (`{{var}}`, `<<var>>`, `${var}`, `[[var]]`)
- Connect `.xlsx` data sources with multi-sheet support and live data preview
- Auto-match spreadsheet columns to template placeholders
- Field transformations: uppercase, lowercase, title case, date formatting, currency, and number formatting
- Custom output filename patterns using dynamic placeholders
- Batch PDF generation — individual files per record or a single combined PDF
- ZIP archive output for multi-file exports

### Job Management
- Organize jobs into categories with custom icons and colors
- Track job status: Draft, Configured, Running, Completed, Failed
- Visual configuration progress indicator across five steps
- Search, rename, and delete jobs with optional confirmation dialogs

### Multi-Platform
- Responsive layout adapts to compact (iPhone) and regular (iPad/Mac) size classes
- `NavigationSplitView` sidebar on macOS and iPad
- macOS menu bar commands (rename, delete) via focused scene values
- Security-scoped bookmark handling for macOS sandboxed file access

### Subscription
- **Free tier:** up to 3 jobs
- **Pro tier:** unlimited jobs, unlimited records, batch output, auto-matching, and all field transformations
- Monthly, annual, and lifetime purchase options via StoreKit 2

---

## Requirements

| Requirement | Version |
|---|---|
| Xcode | 16+ |
| iOS deployment target | 17+ |
| macOS deployment target | 14+ |
| Swift | 6+ |

---

## Build Instructions

### 1. Clone the repository

```bash
git clone <repo-url>
cd MailMerge
```

### 2. Open the project

```bash
open MailMerge.xcodeproj
```

Or open `MailMerge.xcodeproj` directly from Finder.

### 3. Select a scheme and destination

In Xcode's toolbar, choose the **MailMerge** scheme and pick a simulator or connected device.

### 4. Configure signing

1. Select the `MailMerge` project in the Project Navigator.
2. Open the **Signing & Capabilities** tab for the `MailMerge` target.
3. Set your **Team** and update the **Bundle Identifier** if needed.

### 5. Build and run

Press **⌘R** or click the Run button.

> **StoreKit testing:** The project includes `Configuration.storekit`. In Xcode, go to **Edit Scheme → Run → Options** and set the StoreKit Configuration to `Configuration.storekit` to test in-app purchases locally without a sandbox account.

---

## Architecture

### Technology Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI |
| Persistence | SwiftData |
| Payments | StoreKit 2 (FlexStore) |
| Excel parsing | CoreXLSX |
| PDF rendering | PDFKit / UIGraphicsPDFRenderer |
| ZIP output | ZIPFoundation |
| Onboarding | OnboardingKit |

### Project Structure

```
MailMerge/
├── App/
│   ├── MailMergeApp.swift       # App entry point, SwiftData container, StoreKit setup
│   └── MainTabView.swift        # Root navigation (tab bar on iOS, split view on macOS)
├── Features/
│   ├── Jobs/
│   │   ├── JobsListView.swift       # Job list with search, categories, and creation
│   │   ├── JobDetailView.swift      # Tabbed job detail with step-based configuration
│   │   ├── TemplateConfigView.swift # DOCX template selection and placeholder preview
│   │   ├── DataSourceConfigView.swift # Excel file and sheet selection
│   │   ├── FieldMappingConfigView.swift # Column-to-placeholder mapping with transforms
│   │   ├── OutputConfigView.swift   # Filename pattern and output folder configuration
│   │   └── PreviewConfigView.swift  # Single-record preview and batch merge trigger
│   ├── Onboarding/
│   │   └── OnboardingContent.swift  # First-launch onboarding screens
│   └── Paywall/
│       ├── MailMergeTier.swift      # Free/Pro tier logic and job limit enforcement
│       ├── PaywallView.swift        # Subscription purchase UI
│       └── StoreContent.swift       # Paywall copy and feature list
├── Shared/
│   ├── Models/
│   │   └── Models.swift             # SwiftData models (MailMergeJob, FieldMapping, Category)
│   ├── Services/
│   │   └── Services.swift           # DOCXParserService, ExcelParserService, PDFGeneratorService, MergeEngine, ServiceContainer
│   └── UI/
│       └── UIComponents.swift       # Reusable SwiftUI components
└── Resources/
    ├── Assets.xcassets
    ├── Configuration.storekit       # Local StoreKit configuration for testing
    ├── MailMerge.entitlements
    └── PrivacyInfo.xcprivacy
```

### Data Models

**`MailMergeJob`** — the primary model. Stores file bookmarks (security-scoped on macOS), sheet selection, field mappings, job status, and a computed configuration progress value (0–1 across five steps).

**`FieldMapping`** — links a template placeholder to a spreadsheet column, with an optional transformation and auto-match confidence score.

**`Category`** — groups jobs with a custom icon, color, and sort order. A locked system category (Uncategorized) is always present.

Schema versioning is handled via a SwiftData migration plan across three versions (V1 → V2 added categories; V2 → V3 is a lightweight migration).

### Service Layer

All services are accessed through a `ServiceContainer` singleton injected into the SwiftUI environment.

- **`DOCXParserService`** (actor) — extracts placeholders and header images from DOCX files using ZIPFoundation and NSAttributedString.
- **`ExcelParserService`** (actor) — reads sheet names, column headers, and row data from XLSX files via CoreXLSX.
- **`PDFGeneratorService`** — renders attributed strings to PDF pages using PDFKit (macOS) or `UIGraphicsPDFRenderer` (iOS).
- **`MergeEngine`** — orchestrates the full merge workflow: template analysis, data loading, field substitution, transformation, and output file writing.

---

## Running Tests

Tests live in the `MailMergeTests` target.

```bash
# Run all tests from the command line
xcodebuild test -project MailMerge.xcodeproj -scheme MailMerge -destination 'platform=iOS Simulator,name=iPhone 16'
```

Or press **⌘U** in Xcode.
