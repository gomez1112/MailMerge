import Foundation
import SwiftData
import Testing
@testable import Mergeform

/// An in-memory store. Keep the container alive for as long as the context is used.
@MainActor
private func makeStore() throws -> (container: ModelContainer, context: ModelContext) {
    let schema = Schema(versionedSchema: MailMergeSchemaV3.self)
    let container = try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    )
    return (container, container.mainContext)
}

/// A job with every file chosen, ready apart from its field mappings.
@MainActor
private func makeJobWithFiles(in context: ModelContext) -> MailMergeJob {
    let job = MailMergeJob(name: "Letters")
    context.insert(job)
    job.templateBookmarkData = Data([1])
    job.dataSourceBookmarkData = Data([1])
    job.selectedSheetName = "Sheet1"
    job.outputFolderBookmarkData = Data([1])
    return job
}

@MainActor
@Suite("Categories")
struct CategoryManagementTests {
    @Test("The locked Uncategorized category can't be deleted")
    func lockedCategoryIsKept() throws {
        let store = try makeStore()
        let uncategorized = Mergeform.Category(name: "Uncategorized", sortOrder: 0, isLocked: true)
        store.context.insert(uncategorized)
        let job = MailMergeJob(name: "Letters", category: uncategorized)
        store.context.insert(job)

        Mergeform.Category.delete(uncategorized, jobs: [job], fallback: uncategorized, in: store.context)
        try store.context.save()

        let remaining = try store.context.fetch(FetchDescriptor<Mergeform.Category>())
        #expect(remaining.map(\.name) == ["Uncategorized"])
        #expect(job.category?.name == "Uncategorized")
    }

    @Test("Deleting a category moves its jobs to Uncategorized")
    func jobsMoveToFallback() throws {
        let store = try makeStore()
        let uncategorized = Mergeform.Category(name: "Uncategorized", sortOrder: 0, isLocked: true)
        let work = Mergeform.Category(name: "Work", sortOrder: 2)
        store.context.insert(uncategorized)
        store.context.insert(work)
        let job = MailMergeJob(name: "Letters", category: work)
        store.context.insert(job)

        Mergeform.Category.delete(work, jobs: [job], fallback: uncategorized, in: store.context)
        #expect(job.category?.name == "Uncategorized")
    }

    @Test("A missing Uncategorized category is recreated and collects jobs without a category")
    func uncategorizedIsRestored() throws {
        let store = try makeStore()
        let work = Mergeform.Category(name: "Work", sortOrder: 2)
        store.context.insert(work)
        let job = MailMergeJob(name: "Letters")
        store.context.insert(job)

        Mergeform.Category.ensureDefaults(categories: [work], jobs: [job], in: store.context)

        let locked = try store.context.fetch(FetchDescriptor<Mergeform.Category>()).filter(\.isLocked)
        #expect(locked.map(\.name) == ["Uncategorized"])
        #expect(job.category?.name == "Uncategorized")
    }
}

@MainActor
@Suite("Job readiness")
struct JobReadinessTests {
    @Test("A data source without a chosen sheet isn't complete")
    func dataSourceNeedsSheet() throws {
        let store = try makeStore()
        let job = makeJobWithFiles(in: store.context)
        job.selectedSheetName = nil
        #expect(job.hasDataSource == false)
    }

    @Test("A job with no mapped fields isn't ready to run")
    func needsAMappedField() throws {
        let store = try makeStore()
        let job = makeJobWithFiles(in: store.context)
        job.fieldMappings = [FieldMapping(placeholderText: "Name", job: job)]
        #expect(job.hasFieldMappings == false)
        #expect(job.isConfigured == false)

        job.fieldMappings[0].columnName = "Name"
        #expect(job.hasFieldMappings)
        #expect(job.isConfigured)
    }

    @Test("Jobs left running by an interrupted merge are reset at launch")
    func interruptedRunsAreReset() throws {
        let store = try makeStore()
        let configured = makeJobWithFiles(in: store.context)
        configured.fieldMappings = [FieldMapping(placeholderText: "Name", columnName: "Name", job: configured)]
        configured.status = .running
        let draft = MailMergeJob(name: "Draft", status: .running)
        store.context.insert(draft)
        try store.context.save()

        try MailMergeJob.resetInterruptedRuns(in: store.context)

        #expect(configured.status == .configured)
        #expect(draft.status == .draft)
    }
}

@MainActor
@Suite("Field mappings")
struct FieldMappingSyncTests {
    @Test("Rescanning keeps current fields, adds new ones, and removes ones the template no longer has")
    func syncReplacesStaleFields() throws {
        let store = try makeStore()
        let job = makeJobWithFiles(in: store.context)
        job.fieldMappings = [
            FieldMapping(placeholderText: "Old", columnName: "Old", job: job),
            FieldMapping(placeholderText: "Keep", columnName: "Keep Column", job: job)
        ]

        job.syncFieldMappings(with: ["Keep", "New"], in: store.context)

        #expect(Set(job.fieldMappings.map(\.placeholderText)) == ["Keep", "New"])
        #expect(job.fieldMappings.first { $0.placeholderText == "Keep" }?.columnName == "Keep Column")
    }

    @Test("Fields that differ only by spacing are merged into one")
    func spacingDuplicatesAreMerged() throws {
        let store = try makeStore()
        let job = makeJobWithFiles(in: store.context)
        job.fieldMappings = [
            FieldMapping(placeholderText: " First ", job: job),
            FieldMapping(placeholderText: "First", columnName: "First Name", job: job)
        ]

        job.syncFieldMappings(with: ["First"], in: store.context)

        #expect(job.fieldMappings.count == 1)
        #expect(job.fieldMappings.first?.columnName == "First Name")
    }

    @Test("Mappings to columns that no longer exist are cleared")
    func renamedColumnsClearMappings() throws {
        let store = try makeStore()
        let job = makeJobWithFiles(in: store.context)
        let mapping = FieldMapping(placeholderText: "First", columnName: "First Name", isAutoMatched: true, matchConfidence: 1, job: job)
        job.fieldMappings = [mapping]

        job.updateAvailableColumns(["FirstName", "Last Name"])

        #expect(mapping.columnName == nil)
        #expect(mapping.isAutoMatched == false)
        #expect(job.availableColumns == ["FirstName", "Last Name"])
    }
}

@MainActor
@Suite("Auto-match")
struct FieldAutoMatcherTests {
    @Test("Each column is suggested for at most one field")
    func columnsAreUsedOnce() {
        let matches = FieldAutoMatcher.matches(fields: ["Email", "E-mail"], columns: ["Email"])
        #expect(matches.count == 1)
        #expect(matches["Email"]?.column == "Email")
    }

    @Test("Short names that merely look alike aren't matched")
    func lookalikesAreRejected() {
        #expect(FieldAutoMatcher.matches(fields: ["Date"], columns: ["State"]).isEmpty)
    }

    @Test("A column whose name starts or ends with the field's name is matched")
    func prefixesMatch() {
        #expect(FieldAutoMatcher.matches(fields: ["Zip"], columns: ["Zip Code"])["Zip"]?.column == "Zip Code")
    }

    @Test("Columns already mapped by hand aren't suggested again")
    func columnsInUseAreSkipped() {
        #expect(FieldAutoMatcher.matches(fields: ["Email"], columns: ["Email"], columnsInUse: ["Email"]).isEmpty)
    }
}

@MainActor
@Suite("Transformations and formats")
struct TransformationFormatTests {
    @Test("Title Case capitalizes words without breaking ordinals or hyphenated names", arguments: [
        ("3rd street", "3rd Street"),
        ("mary-jane o'neil", "Mary-Jane O'neil"),
        ("MCDONALD", "Mcdonald"),
        ("hello world", "Hello World")
    ])
    func titleCase(input: String, expected: String) {
        #expect(FieldTransformation.titlecase.apply(to: input, formatString: nil) == expected)
    }

    @Test("Short dates from Excel keep their century")
    func twoDigitYears() {
        #expect(FieldTransformation.dateFormat.apply(to: "1/15/24", formatString: "yyyy-MM-dd") == "2024-01-15")
    }

    @Test("Plain numbers aren't read as Unix timestamps")
    func plainNumbersAreNotDates() {
        #expect(DateParser.parse("2024") == nil)
        #expect(DateParser.parse("45306") == nil)
    }

    @Test("Month names parse regardless of the Mac's region")
    func monthNamesInOtherRegions() {
        #expect(DateParser.parse("Jan 2, 2024", locale: Locale(identifier: "fr_FR")) != nil)
    }

    @Test("Numeric dates follow the region's day and month order")
    func regionalDateOrder() throws {
        let date = try #require(DateParser.parse("03/04/2024", locale: Locale(identifier: "en_GB")))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        #expect(calendar.component(.month, from: date) == 4)
        #expect(calendar.component(.day, from: date) == 3)
    }

    @Test("Number Format accepts numbers with thousands separators")
    func groupedNumbers() {
        #expect(FieldTransformation.numberFormat.apply(to: "1,234.5", formatString: "#,##0.00") == "1,234.50")
    }

    @Test("Formatting transformations start with a sensible format")
    func defaultFormats() {
        #expect(FieldTransformation.dateFormat.defaultFormatString() == "MMMM d, yyyy")
        #expect(FieldTransformation.numberFormat.defaultFormatString() == "#,##0.00")
        #expect(FieldTransformation.currencyFormat.defaultFormatString(locale: Locale(identifier: "en_US")) == "USD")
        #expect(FieldTransformation.uppercase.defaultFormatString() == nil)
    }
}
