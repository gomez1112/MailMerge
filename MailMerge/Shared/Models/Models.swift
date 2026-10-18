import Foundation
import SwiftData

@Model
final class MailMergeJob {
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var templateBookmarkData: Data?
    var templateFileName: String?
    var dataSourceBookmarkData: Data?
    var dataSourceFileName: String?
    var selectedSheetName: String?
    var availableSheets: [String]
    @Transient var availableColumns: [String] = []
    var combineIntoSinglePDF: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \FieldMapping.job)
    var fieldMappings: [FieldMapping]
    var outputFolderBookmarkData: Data?
    var outputFolderName: String?
    var outputFileNamePattern: String
    var status: JobStatus
    var lastRunDate: Date?
    var lastRunRecordCount: Int?
    var category: Category?

    init(
        name: String,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        templateBookmarkData: Data? = nil,
        templateFileName: String? = nil,
        dataSourceBookmarkData: Data? = nil,
        dataSourceFileName: String? = nil,
        selectedSheetName: String? = nil,
        availableSheets: [String] = [],
        availableColumns: [String] = [],
        combineIntoSinglePDF: Bool = false,
        fieldMappings: [FieldMapping] = [],
        outputFolderBookmarkData: Data? = nil,
        outputFolderName: String? = nil,
        outputFileNamePattern: String = "Letter_{FirstName}_{LastName}",
        status: JobStatus = .draft,
        lastRunDate: Date? = nil,
        lastRunRecordCount: Int? = nil,
        category: Category? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.templateBookmarkData = templateBookmarkData
        self.templateFileName = templateFileName
        self.dataSourceBookmarkData = dataSourceBookmarkData
        self.dataSourceFileName = dataSourceFileName
        self.selectedSheetName = selectedSheetName
        self.availableSheets = availableSheets
        self.availableColumns = availableColumns
        self.combineIntoSinglePDF = combineIntoSinglePDF
        self.fieldMappings = fieldMappings
        self.outputFolderBookmarkData = outputFolderBookmarkData
        self.outputFolderName = outputFolderName
        self.outputFileNamePattern = outputFileNamePattern
        self.status = status
        self.lastRunDate = lastRunDate
        self.lastRunRecordCount = lastRunRecordCount
        self.category = category
    }

    /// Every setup step is complete and the job can run.
    var isConfigured: Bool {
        hasTemplate && hasDataSource && hasFieldMappings && hasOutputFolder
    }

    /// Re-creates bookmarks to files that moved or were renamed since they were picked,
    /// and updates the names shown for them.
    func refreshStaleBookmarks() {
        if let data = templateBookmarkData, let refreshed = SecurityScopedAccess.refreshedBookmark(for: data) {
            templateBookmarkData = refreshed.bookmark
            templateFileName = refreshed.url.lastPathComponent
        }
        if let data = dataSourceBookmarkData, let refreshed = SecurityScopedAccess.refreshedBookmark(for: data) {
            dataSourceBookmarkData = refreshed.bookmark
            dataSourceFileName = refreshed.url.lastPathComponent
        }
        if let data = outputFolderBookmarkData, let refreshed = SecurityScopedAccess.refreshedBookmark(for: data) {
            outputFolderBookmarkData = refreshed.bookmark
            outputFolderName = refreshed.url.lastPathComponent
        }
    }

    var configurationProgress: Double {
        let total: Double = 5
        var score: Double = 0
        if templateBookmarkData != nil { score += 1 }
        if dataSourceBookmarkData != nil { score += 1 }
        if selectedSheetName != nil { score += 1 }
        if hasFieldMappings { score += 1 }
        if outputFolderBookmarkData != nil { score += 1 }
        return score / total
    }
}

@Model
final class Category {
    var id: UUID
    var name: String
    var systemImageName: String
    var colorName: String
    var sortOrder: Int
    var isLocked: Bool

    init(
        name: String,
        systemImageName: String = "folder",
        colorName: String = "gray",
        sortOrder: Int = 0,
        isLocked: Bool = false,
        id: UUID = UUID()
    ) {
        self.name = name
        self.systemImageName = systemImageName
        self.colorName = colorName
        self.sortOrder = sortOrder
        self.isLocked = isLocked
        self.id = id
    }
}

@Model
final class FieldMapping {
    var placeholderText: String
    var columnName: String?
    var isAutoMatched: Bool
    var matchConfidence: Double
    var transformation: FieldTransformation
    var formatString: String?
    var job: MailMergeJob?

    init(
        placeholderText: String,
        columnName: String? = nil,
        isAutoMatched: Bool = false,
        matchConfidence: Double = 0,
        transformation: FieldTransformation = .none,
        formatString: String? = nil,
        job: MailMergeJob? = nil
    ) {
        self.placeholderText = placeholderText
        self.columnName = columnName
        self.isAutoMatched = isAutoMatched
        self.matchConfidence = matchConfidence
        self.transformation = transformation
        self.formatString = formatString
        self.job = job
    }

    var isMapped: Bool {
        columnName != nil
    }

    var displayName: String {
        TemplatePlaceholders.fieldName(for: placeholderText)
    }
}

enum JobStatus: String, Codable, CaseIterable {
    case draft
    case configured
    case running
    case completed
    case failed

    var label: String {
        switch self {
        case .draft: return "Draft"
        case .configured: return "Configured"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    /// The symbol for the status. Badges, job rows, and the job summary all use it, so
    /// a status looks the same everywhere.
    var systemImageName: String {
        switch self {
        case .draft: return "pencil"
        case .configured: return "checkmark.seal.fill"
        case .running: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

enum FieldTransformation: String, Codable, CaseIterable, Identifiable {
    case none
    case uppercase
    case lowercase
    case titlecase
    case trim
    case dateFormat
    case numberFormat
    case currencyFormat

    var id: String { rawValue }

    /// Whether this transformation uses a format: a date pattern, a number pattern, or
    /// a currency code.
    var usesFormatString: Bool {
        switch self {
        case .dateFormat, .numberFormat, .currencyFormat: return true
        default: return false
        }
    }

    /// The format a mapping starts with when this transformation is chosen.
    func defaultFormatString(locale: Locale = .current) -> String? {
        switch self {
        case .dateFormat: return "MMMM d, yyyy"
        case .numberFormat: return "#,##0.00"
        case .currencyFormat: return locale.currency?.identifier ?? "USD"
        default: return nil
        }
    }

    /// What the format field asks for, with an example.
    var formatPrompt: String {
        switch self {
        case .dateFormat: return "Date pattern, e.g. MMMM d, yyyy"
        case .numberFormat: return "Number pattern, e.g. #,##0.00"
        case .currencyFormat: return "Currency code, e.g. USD"
        default: return ""
        }
    }

    var label: String {
        switch self {
        case .none: return "None"
        case .uppercase: return "Uppercase"
        case .lowercase: return "Lowercase"
        case .titlecase: return "Title Case"
        case .trim: return "Trim"
        case .dateFormat: return "Date Format"
        case .numberFormat: return "Number Format"
        case .currencyFormat: return "Currency Format"
        }
    }

    func apply(to value: String, formatString: String?) -> String {
        switch self {
        case .none:
            return value
        case .uppercase:
            return value.uppercased()
        case .lowercase:
            return value.lowercased()
        case .titlecase:
            return Self.titleCased(value)
        case .trim:
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .dateFormat:
            guard let formatString, !formatString.isEmpty, let date = DateParser.parse(value) else { return value }
            // The pattern is user-entered at runtime, which Date.FormatStyle can't take.
            let formatter = DateFormatter()
            formatter.timeZone = .gmt
            formatter.dateFormat = formatString
            return formatter.string(from: date)
        case .numberFormat:
            guard let formatString, !formatString.isEmpty, let number = Self.parseNumber(value) else { return value }
            // A user-entered ICU pattern like "#,##0.00" needs NumberFormatter.
            let formatter = NumberFormatter()
            formatter.positiveFormat = formatString
            return formatter.string(from: NSNumber(value: number)) ?? value
        case .currencyFormat:
            guard let number = Self.parseNumber(value) else { return value }
            let requestedCode = formatString?.trimmingCharacters(in: .whitespaces).uppercased()
            let code = requestedCode.flatMap { $0.count == 3 && $0.allSatisfy(\.isLetter) ? $0 : nil }
                ?? Locale.current.currency?.identifier
                ?? "USD"
            return number.formatted(.currency(code: code))
        }
    }

    /// Capitalizes the first letter of each word and lowercases the rest. A letter after
    /// a digit or apostrophe continues its word, so "3rd" and "o'neil" stay intact, while
    /// hyphens start a new word ("Mary-Jane").
    private static func titleCased(_ value: String) -> String {
        var result = ""
        var previous: Character?
        for character in value {
            if character.isLetter {
                let continuesWord = previous.map { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "\u{2019}" } ?? false
                result += continuesWord ? character.lowercased() : character.uppercased()
            } else {
                result.append(character)
            }
            previous = character
        }
        return result
    }

    /// Reads plain numbers ("1234.5") and numbers with grouping separators ("1,234.5").
    /// Text like "NaN" or "inf" isn't a number in a mail merge.
    private static func parseNumber(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = Double(trimmed) ?? (try? Double(trimmed, format: .number))
        guard let number, number.isFinite else { return nil }
        return number
    }
}

enum MergeError: LocalizedError {
    case invalidTemplate
    case invalidSpreadsheet
    case emptySheet
    case sheetNotFound
    case staleBookmark
    case outputAccessDenied
    case noRecords
    case pdfGenerationFailed
    case securityScopeUnavailable
    case featureUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidTemplate: return "The DOCX template appears to be invalid or corrupted."
        case .invalidSpreadsheet: return "The Excel file appears to be invalid or corrupted."
        case .emptySheet: return "The selected sheet contains no data."
        case .sheetNotFound: return "The selected sheet could not be found."
        case .staleBookmark: return "The selected file has moved or is no longer available."
        case .outputAccessDenied: return "The output folder could not be accessed."
        case .noRecords: return "No records were found in the data source."
        case .pdfGenerationFailed: return "Failed to generate the PDF output."
        case .securityScopeUnavailable: return "The app could not access the selected file."
        case .featureUnavailable: return "This feature isn't available on the current platform."
        }
    }
}

struct SheetData: Equatable {
    let headers: [String]
    let rows: [[String]]
}

struct MergeResult {
    /// The names of the PDFs the merge saved, in record order. A combined merge saves one.
    let savedFileNames: [String]
    /// The name of the folder the PDFs were saved in.
    let outputFolderName: String
    /// A bookmark to that folder, for showing the PDFs in Finder after the merge has
    /// given up access to it.
    let outputFolderBookmark: Data
    let attachmentURL: URL?
    let recordCount: Int
    let duration: TimeInterval
}

/// How far a merge has come. `total` is zero while the data is still loading.
struct MergeProgress: Equatable {
    var completed: Int
    var total: Int
}

enum MergeStep: Int, CaseIterable, Identifiable {
    case template
    case dataSource
    case fieldMapping
    case output
    case preview

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .template: return "Template"
        case .dataSource: return "Data Source"
        case .fieldMapping: return "Field Mapping"
        case .output: return "Output"
        case .preview: return "Preview"
        }
    }

    /// What the step asks for, in a few words.
    var summary: String {
        switch self {
        case .template: return "Choose a Word document"
        case .dataSource: return "Pick a spreadsheet"
        case .fieldMapping: return "Match fields to columns"
        case .output: return "Choose where PDFs go"
        case .preview: return "Check and run"
        }
    }

    var systemImageName: String {
        switch self {
        case .template: return "richtext.page"
        case .dataSource: return "tablecells"
        case .fieldMapping: return "arrow.left.arrow.right"
        case .output: return "folder"
        case .preview: return "richtext.page"
        }
    }
}

/// Reads the date text that appears in spreadsheets: the region's numeric dates (as the
/// spreadsheet reader writes them), ISO 8601, written-out English month names, and Unix
/// timestamps. Dates are midnight UTC so formatting them never shifts the day.
enum DateParser {
    static func parse(_ value: String, locale: Locale = .current) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let number = TimeInterval(trimmed) {
            // Only ten-digit (or longer) numbers are timestamps; shorter ones are years,
            // ZIP codes, or Excel serial numbers, not dates.
            return abs(number) >= 1_000_000_000 ? Date(timeIntervalSince1970: number) : nil
        }
        if let date = try? Date(trimmed, strategy: .iso8601) {
            return date
        }

        let hasFourDigitYear = trimmed.split(whereSeparator: { !$0.isNumber }).contains { $0.count == 4 }
        let regionalPattern = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale) ?? "M/d/y"
        let numericPattern = regionalPattern.replacing(/y+/, with: hasFourDigitYear ? "yyyy" : "yy")
        if let date = date(from: trimmed, pattern: numericPattern, locale: locale) {
            return date
        }

        let englishPatterns = [
            "yyyy-MM-dd", "MMM d, yyyy", "MMMM d, yyyy", "MMM d yyyy", "d MMM yyyy", "d MMMM yyyy",
            hasFourDigitYear ? "M/d/yyyy" : "M/d/yy"
        ]
        for pattern in englishPatterns {
            if let date = date(from: trimmed, pattern: pattern, locale: Locale(identifier: "en_US_POSIX")) {
                return date
            }
        }
        return nil
    }

    private static func date(from text: String, pattern: String, locale: Locale) -> Date? {
        // Patterns are chosen at runtime from the region, which needs DateFormatter.
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .gmt
        formatter.isLenient = false
        formatter.dateFormat = pattern
        return formatter.date(from: text)
    }
}

enum FileNameSanitizer {
    static func sanitize(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let components = value.components(separatedBy: invalidCharacters)
        return components.joined(separator: "_")
    }
}

enum MailMergeSchemaV1: VersionedSchema {
    static let versionIdentifier: Schema.Version = .init(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MailMergeJobV1.self, FieldMappingV1.self]
    }
}

@Model
final class MailMergeJobV1 {
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var templateBookmarkData: Data?
    var templateFileName: String?
    var dataSourceBookmarkData: Data?
    var dataSourceFileName: String?
    var selectedSheetName: String?
    var availableSheets: [String]
    @Relationship(deleteRule: .cascade, inverse: \FieldMappingV1.job)
    var fieldMappings: [FieldMappingV1]
    var outputFolderBookmarkData: Data?
    var outputFolderName: String?
    var outputFileNamePattern: String
    var status: JobStatus
    var lastRunDate: Date?
    var lastRunRecordCount: Int?
    var category: JobCategoryV1?

    init(
        name: String,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        templateBookmarkData: Data? = nil,
        templateFileName: String? = nil,
        dataSourceBookmarkData: Data? = nil,
        dataSourceFileName: String? = nil,
        selectedSheetName: String? = nil,
        availableSheets: [String] = [],
        fieldMappings: [FieldMappingV1] = [],
        outputFolderBookmarkData: Data? = nil,
        outputFolderName: String? = nil,
        outputFileNamePattern: String = "Letter_{FirstName}_{LastName}",
        status: JobStatus = .draft,
        lastRunDate: Date? = nil,
        lastRunRecordCount: Int? = nil,
        category: JobCategoryV1? = nil
    ) {
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.templateBookmarkData = templateBookmarkData
        self.templateFileName = templateFileName
        self.dataSourceBookmarkData = dataSourceBookmarkData
        self.dataSourceFileName = dataSourceFileName
        self.selectedSheetName = selectedSheetName
        self.availableSheets = availableSheets
        self.fieldMappings = fieldMappings
        self.outputFolderBookmarkData = outputFolderBookmarkData
        self.outputFolderName = outputFolderName
        self.outputFileNamePattern = outputFileNamePattern
        self.status = status
        self.lastRunDate = lastRunDate
        self.lastRunRecordCount = lastRunRecordCount
        self.category = category
    }
}

@Model
final class FieldMappingV1 {
    var placeholderText: String
    var columnName: String?
    var isAutoMatched: Bool
    var matchConfidence: Double
    var transformation: FieldTransformation
    var formatString: String?
    var job: MailMergeJobV1?

    init(
        placeholderText: String,
        columnName: String? = nil,
        isAutoMatched: Bool = false,
        matchConfidence: Double = 0,
        transformation: FieldTransformation = .none,
        formatString: String? = nil,
        job: MailMergeJobV1? = nil
    ) {
        self.placeholderText = placeholderText
        self.columnName = columnName
        self.isAutoMatched = isAutoMatched
        self.matchConfidence = matchConfidence
        self.transformation = transformation
        self.formatString = formatString
        self.job = job
    }
}

enum JobCategoryV1: String, Codable, CaseIterable {
    case uncategorized
    case personal
    case work
    case marketing
    case events
    case archived
}

@Model
final class MailMergeJobV2 {
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var templateBookmarkData: Data?
    var templateFileName: String?
    var dataSourceBookmarkData: Data?
    var dataSourceFileName: String?
    var selectedSheetName: String?
    var availableSheets: [String]
    @Transient var availableColumns: [String] = []
    @Relationship(deleteRule: .cascade, inverse: \FieldMappingV2.job)
    var fieldMappings: [FieldMappingV2]
    var outputFolderBookmarkData: Data?
    var outputFolderName: String?
    var outputFileNamePattern: String
    var status: JobStatus
    var lastRunDate: Date?
    var lastRunRecordCount: Int?
    var category: CategoryV2?

    init(
        name: String,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        templateBookmarkData: Data? = nil,
        templateFileName: String? = nil,
        dataSourceBookmarkData: Data? = nil,
        dataSourceFileName: String? = nil,
        selectedSheetName: String? = nil,
        availableSheets: [String] = [],
        fieldMappings: [FieldMappingV2] = [],
        outputFolderBookmarkData: Data? = nil,
        outputFolderName: String? = nil,
        outputFileNamePattern: String = "Letter_{FirstName}_{LastName}",
        status: JobStatus = .draft,
        lastRunDate: Date? = nil,
        lastRunRecordCount: Int? = nil,
        category: CategoryV2? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.templateBookmarkData = templateBookmarkData
        self.templateFileName = templateFileName
        self.dataSourceBookmarkData = dataSourceBookmarkData
        self.dataSourceFileName = dataSourceFileName
        self.selectedSheetName = selectedSheetName
        self.availableSheets = availableSheets
        self.fieldMappings = fieldMappings
        self.outputFolderBookmarkData = outputFolderBookmarkData
        self.outputFolderName = outputFolderName
        self.outputFileNamePattern = outputFileNamePattern
        self.status = status
        self.lastRunDate = lastRunDate
        self.lastRunRecordCount = lastRunRecordCount
        self.category = category
    }
}

@Model
final class CategoryV2 {
    var id: UUID
    var name: String
    var systemImageName: String
    var colorName: String
    var sortOrder: Int
    var isLocked: Bool

    init(
        name: String,
        systemImageName: String = "folder",
        colorName: String = "gray",
        sortOrder: Int = 0,
        isLocked: Bool = false,
        id: UUID = UUID()
    ) {
        self.name = name
        self.systemImageName = systemImageName
        self.colorName = colorName
        self.sortOrder = sortOrder
        self.isLocked = isLocked
        self.id = id
    }
}

@Model
final class FieldMappingV2 {
    var placeholderText: String
    var columnName: String?
    var isAutoMatched: Bool
    var matchConfidence: Double
    var transformation: FieldTransformation
    var formatString: String?
    var job: MailMergeJobV2?

    init(
        placeholderText: String,
        columnName: String? = nil,
        isAutoMatched: Bool = false,
        matchConfidence: Double = 0,
        transformation: FieldTransformation = .none,
        formatString: String? = nil,
        job: MailMergeJobV2? = nil
    ) {
        self.placeholderText = placeholderText
        self.columnName = columnName
        self.isAutoMatched = isAutoMatched
        self.matchConfidence = matchConfidence
        self.transformation = transformation
        self.formatString = formatString
        self.job = job
    }
}

enum MailMergeSchemaV2: VersionedSchema {
    static let versionIdentifier: Schema.Version = .init(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MailMergeJobV2.self, FieldMappingV2.self, CategoryV2.self]
    }
}

enum MailMergeSchemaV3: VersionedSchema {
    static let versionIdentifier: Schema.Version = .init(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MailMergeJob.self, FieldMapping.self, Category.self]
    }
}

enum MailMergeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MailMergeSchemaV1.self, MailMergeSchemaV2.self, MailMergeSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: MailMergeSchemaV1.self,
        toVersion: MailMergeSchemaV2.self,
        willMigrate: { context in
            let jobs = try context.fetch(FetchDescriptor<MailMergeJobV1>())
            let defaults = [
                CategoryV2(name: "Uncategorized", systemImageName: "tray", colorName: "gray", sortOrder: 0, isLocked: true),
                CategoryV2(name: "Personal", systemImageName: "person", colorName: "blue", sortOrder: 1, isLocked: false),
                CategoryV2(name: "Work", systemImageName: "briefcase", colorName: "purple", sortOrder: 2, isLocked: false),
                CategoryV2(name: "Marketing", systemImageName: "megaphone", colorName: "orange", sortOrder: 3, isLocked: false),
                CategoryV2(name: "Events", systemImageName: "calendar", colorName: "green", sortOrder: 4, isLocked: false),
                CategoryV2(name: "Archived", systemImageName: "archivebox", colorName: "brown", sortOrder: 5, isLocked: false)
            ]
            for category in defaults {
                context.insert(category)
            }
            let categoryMap: [JobCategoryV1?: CategoryV2] = [
                .uncategorized: defaults[0],
                .personal: defaults[1],
                .work: defaults[2],
                .marketing: defaults[3],
                .events: defaults[4],
                .archived: defaults[5],
                nil: defaults[0]
            ]

            for job in jobs {
                let newJob = MailMergeJobV2(
                    name: job.name,
                    id: UUID(),
                    createdAt: job.createdAt,
                    modifiedAt: job.modifiedAt,
                    templateBookmarkData: job.templateBookmarkData,
                    templateFileName: job.templateFileName,
                    dataSourceBookmarkData: job.dataSourceBookmarkData,
                    dataSourceFileName: job.dataSourceFileName,
                    selectedSheetName: job.selectedSheetName,
                    availableSheets: job.availableSheets,
                    fieldMappings: [],
                    outputFolderBookmarkData: job.outputFolderBookmarkData,
                    outputFolderName: job.outputFolderName,
                    outputFileNamePattern: job.outputFileNamePattern,
                    status: job.status,
                    lastRunDate: job.lastRunDate,
                    lastRunRecordCount: job.lastRunRecordCount,
                    category: categoryMap[job.category]
                )
                for mapping in job.fieldMappings {
                    let newMapping = FieldMappingV2(
                        placeholderText: mapping.placeholderText,
                        columnName: mapping.columnName,
                        isAutoMatched: mapping.isAutoMatched,
                        matchConfidence: mapping.matchConfidence,
                        transformation: mapping.transformation,
                        formatString: mapping.formatString,
                        job: newJob
                    )
                    newJob.fieldMappings.append(newMapping)
                }
                context.insert(newJob)
            }
        },
        didMigrate: { _ in }
    )

    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: MailMergeSchemaV2.self,
        toVersion: MailMergeSchemaV3.self
    )
}
