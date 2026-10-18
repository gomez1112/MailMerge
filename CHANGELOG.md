# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - 2026-10-17

### Added
- Redesigned interface: native sidebar, shared design system, step rail, and animations that respect Reduce Motion
- Full Dark Mode support, with colors that match the app icon and Increase Contrast variants
- The merge result shows which folder the PDFs were saved in, with Show in Finder; the Output step can also show its folder in Finder
- Cancelling a merge stops it at the next record; merge progress and results persist while moving between steps
- Drag and drop for templates, spreadsheets, and output folders
- Format fields for Date, Number, and Currency transformations, with a live example
- Confirmation before deleting a job, controlled by the existing setting
- The app icon in the sidebar, paywall, and Settings > About

### Changed
- Spreadsheets are read by a built-in tolerant reader that applies Excel's number formats; CoreXLSX was removed and ZIPFoundation is a direct dependency
- PDFs use the template's paper size, margins, and header picture size
- Field auto-matching uses each column once and rejects look-alike names
- The paywall offers what Pro actually unlocks (unlimited jobs) and uses StoreKit's subscription store

### Fixed
- Excel values: leading zeros, percentages, dates in styled workbooks, rich text, formula noise, booleans, large numbers, and the 1904 date system
- Placeholder edge cases and output file names (hidden, duplicate, or overly long names)
- Jobs whose files were moved or renamed
- Changing a template left stale fields; renamed columns left stale mappings
- Job navigation, Job menu targeting, New Job routing, and Command-Delete while typing
- Add, Rename, and Delete in Manage Categories; the Uncategorized category could be deleted
- Lifetime purchases shown as Free; settings that had no effect; relative dates reading as future dates
- Combined PDFs freezing the app, and jobs left "Running" after a quit

## [1.0.0] - 2026-02-17

### Added
- Initial public release of Mergeform
- DOCX template parsing with support for `{{var}}`, `<<var>>`, `${var}`, and `[[var]]` placeholder formats
- Excel (`.xlsx`) data source import with multi-sheet support and live data preview
- Field mapping with auto-match and per-field confidence scoring
- Field transformations: uppercase, lowercase, title case, date formatting, currency, and number formatting
- Custom output filename patterns using dynamic placeholders
- Batch PDF generation — individual files per record or a single combined PDF
- ZIP archive output for multi-file exports
- Job organization with categories (custom icon and color)
- Job status tracking: Draft, Configured, Running, Completed, Failed
- Visual five-step configuration progress indicator per job
- Search across jobs
- Free tier (up to 3 jobs) and Pro tier (unlimited) via StoreKit 2
- Monthly, annual, and lifetime Pro purchase options
- In-app paywall with feature showcase
- Restore purchases support
- First-launch onboarding screens
- App icon
- iPad and macOS support with `NavigationSplitView` sidebar
- macOS menu bar commands (rename, delete) via focused scene values
- Security-scoped bookmark handling for macOS sandboxed file access
- SwiftData persistence with schema versioning and migration plan (V1 → V2 → V3)
- Local StoreKit configuration for sandbox testing

### Fixed
- Navigation issues on initial launch
- UI layout and rendering bugs across iOS and iPadOS
- Various stability and crash fixes identified during development

[Unreleased]: https://github.com/gerardgomez/MailMerge/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/gerardgomez/MailMerge/compare/v1.0.0...v1.2.0
[1.0.0]: https://github.com/gerardgomez/MailMerge/releases/tag/v1.0.0
