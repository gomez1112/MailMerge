# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/gerardgomez/MailMerge/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/gerardgomez/MailMerge/releases/tag/v1.0.0
