import Foundation
import SwiftData

// MARK: - Setup Readiness

extension MailMergeJob {
    var hasTemplate: Bool { templateBookmarkData != nil }

    /// A spreadsheet is chosen and one of its sheets is selected.
    var hasDataSource: Bool { dataSourceBookmarkData != nil && selectedSheetName != nil }

    var mappedFieldCount: Int { fieldMappings.filter(\.isMapped).count }

    /// At least one template field has a column. Fields without one are left blank.
    var hasFieldMappings: Bool { mappedFieldCount > 0 }

    var hasOutputFolder: Bool { outputFolderBookmarkData != nil }

    /// A new job that uses the default file name pattern from Settings.
    static func makeNew(name: String, category: Category?, defaults: UserDefaults = .standard) -> MailMergeJob {
        let job = MailMergeJob(name: name, category: category)
        if let pattern = defaults.string(forKey: "defaultOutputPattern")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !pattern.isEmpty {
            job.outputFileNamePattern = pattern
        }
        return job
    }

    /// When the job was last changed, for the job list: relative ("2 hours ago") or the
    /// date and time, per the "Show relative dates" setting.
    func modifiedDescription(relative: Bool, relativeTo now: Date = .now) -> String {
        if relative {
            // The anchored style describes its anchor relative to the date it formats, so
            // the modification date is the anchor and "now" is what's formatted.
            let style = Date.AnchoredRelativeFormatStyle(anchor: modifiedAt, presentation: .named)
            return "Modified \(style.format(now))"
        }
        return "Modified \(modifiedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    /// Maps fields without a column to the best-matching columns.
    func autoMatchUnmappedFields() {
        autoMatch(fieldMappings.filter { !$0.isMapped })
    }

    private func autoMatch(_ mappings: [FieldMapping]) {
        guard !availableColumns.isEmpty, !mappings.isEmpty else { return }
        let matches = FieldAutoMatcher.matches(
            fields: mappings.map(\.displayName),
            columns: availableColumns,
            columnsInUse: Set(fieldMappings.compactMap(\.columnName))
        )
        for mapping in mappings {
            guard let match = matches[mapping.displayName] else { continue }
            mapping.columnName = match.column
            mapping.isAutoMatched = true
            mapping.matchConfidence = match.confidence
        }
    }

    /// Updates the field list after scanning the template: keeps fields the template
    /// still uses (with their columns), adds new ones, and removes the rest. Fields that
    /// differ only by surrounding spaces count as one.
    func syncFieldMappings(with placeholders: [String], in context: ModelContext?, autoMatch: Bool = false) {
        let fields = Set(
            placeholders
                .map { TemplatePlaceholders.fieldName(for: $0) }
                .filter { !$0.isEmpty }
        )

        var keptByField: [String: FieldMapping] = [:]
        var discarded: [FieldMapping] = []
        for mapping in fieldMappings {
            let field = TemplatePlaceholders.fieldName(for: mapping.placeholderText)
            guard fields.contains(field) else {
                discarded.append(mapping)
                continue
            }
            if let existing = keptByField[field] {
                // Of two entries for one field, keep the one with a column.
                if !existing.isMapped && mapping.isMapped {
                    discarded.append(existing)
                    keptByField[field] = mapping
                } else {
                    discarded.append(mapping)
                }
            } else {
                keptByField[field] = mapping
            }
        }

        for (field, mapping) in keptByField where mapping.placeholderText != field {
            mapping.placeholderText = field
        }
        for mapping in discarded {
            fieldMappings.removeAll { $0 === mapping }
            context?.delete(mapping)
        }
        var added: [FieldMapping] = []
        for field in fields.sorted() where keptByField[field] == nil {
            let mapping = FieldMapping(placeholderText: field, job: self)
            fieldMappings.append(mapping)
            added.append(mapping)
        }
        if autoMatch {
            self.autoMatch(added)
        }
    }

    /// Records the spreadsheet columns fields can be mapped to, and clears mappings to
    /// columns the sheet no longer has, such as after a header was renamed.
    func updateAvailableColumns(_ headers: [String]) {
        let cleanedHeaders = headers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen: Set<String> = []
        let columns = cleanedHeaders.filter { seen.insert($0).inserted }
        availableColumns = columns

        let columnSet = Set(columns)
        for mapping in fieldMappings {
            guard let columnName = mapping.columnName, !columnSet.contains(columnName) else { continue }
            mapping.columnName = nil
            mapping.isAutoMatched = false
            mapping.matchConfidence = 0
        }
    }

    /// Resets jobs a merge left "Running" because the app quit or crashed before it
    /// finished. No merge can be running at launch.
    static func resetInterruptedRuns(in context: ModelContext) throws {
        let jobs = try context.fetch(FetchDescriptor<MailMergeJob>())
        for job in jobs where job.status == .running {
            job.status = job.isConfigured ? .configured : .draft
        }
        if context.hasChanges {
            try context.save()
        }
    }
}

// MARK: - Categories

extension Category {
    /// Seeds the default categories on first launch, makes sure the locked Uncategorized
    /// category exists, and files jobs that have no category into it.
    static func ensureDefaults(categories: [Category], jobs: [MailMergeJob], in context: ModelContext) {
        var uncategorized = categories.first(where: \.isLocked)
        if categories.isEmpty {
            for seed in DefaultCategorySeed.defaults {
                let category = seed.makeCategory()
                context.insert(category)
                if seed.isLocked { uncategorized = category }
            }
        } else if uncategorized == nil {
            let category = DefaultCategorySeed.uncategorized.makeCategory()
            context.insert(category)
            uncategorized = category
        }
        guard let uncategorized else { return }
        for job in jobs {
            let hasKnownCategory = job.category.map { current in
                current === uncategorized || categories.contains { $0 === current }
            } ?? false
            if !hasKnownCategory {
                job.category = uncategorized
            }
        }
    }

    /// Deletes a category and moves its jobs to `fallback`. The locked Uncategorized
    /// category is where jobs go, so it can't be deleted.
    @discardableResult
    static func delete(_ category: Category, jobs: [MailMergeJob], fallback: Category?, in context: ModelContext) -> Bool {
        guard !category.isLocked, let fallback, fallback !== category else { return false }
        for job in jobs where job.category === category {
            job.category = fallback
        }
        context.delete(category)
        return true
    }
}

nonisolated private struct DefaultCategorySeed {
    let name: String
    let systemImageName: String
    let colorName: String
    let sortOrder: Int
    let isLocked: Bool

    static let uncategorized = DefaultCategorySeed(name: "Uncategorized", systemImageName: "tray", colorName: "gray", sortOrder: 0, isLocked: true)

    static let defaults: [DefaultCategorySeed] = [
        uncategorized,
        DefaultCategorySeed(name: "Personal", systemImageName: "person", colorName: "blue", sortOrder: 1, isLocked: false),
        DefaultCategorySeed(name: "Work", systemImageName: "briefcase", colorName: "purple", sortOrder: 2, isLocked: false),
        DefaultCategorySeed(name: "Marketing", systemImageName: "megaphone", colorName: "orange", sortOrder: 3, isLocked: false),
        DefaultCategorySeed(name: "Events", systemImageName: "calendar", colorName: "green", sortOrder: 4, isLocked: false),
        DefaultCategorySeed(name: "Archived", systemImageName: "archivebox", colorName: "brown", sortOrder: 5, isLocked: false)
    ]

    func makeCategory() -> Category {
        Category(name: name, systemImageName: systemImageName, colorName: colorName, sortOrder: sortOrder, isLocked: isLocked)
    }
}
