import Foundation
import SwiftData

@Model
final class MailMergeJob {
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
    @Relationship(deleteRule: .cascade, inverse: \FieldMapping.job)
    var fieldMappings: [FieldMapping]
    var outputFolderBookmarkData: Data?
    var outputFolderName: String?
    var outputFileNamePattern: String
    var status: JobStatus
    var lastRunDate: Date?
    var lastRunRecordCount: Int?

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
        availableColumns: [String] = [],
        fieldMappings: [FieldMapping] = [],
        outputFolderBookmarkData: Data? = nil,
        outputFolderName: String? = nil,
        outputFileNamePattern: String = "Letter_{FirstName}_{LastName}",
        status: JobStatus = .draft,
        lastRunDate: Date? = nil,
        lastRunRecordCount: Int? = nil
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
        self.availableColumns = availableColumns
        self.fieldMappings = fieldMappings
        self.outputFolderBookmarkData = outputFolderBookmarkData
        self.outputFolderName = outputFolderName
        self.outputFileNamePattern = outputFileNamePattern
        self.status = status
        self.lastRunDate = lastRunDate
        self.lastRunRecordCount = lastRunRecordCount
    }

    var isConfigured: Bool {
        templateBookmarkData != nil
            && dataSourceBookmarkData != nil
            && selectedSheetName != nil
            && !fieldMappings.isEmpty
            && outputFolderBookmarkData != nil
    }

    var configurationProgress: Double {
        let total: Double = 5
        var score: Double = 0
        if templateBookmarkData != nil { score += 1 }
        if dataSourceBookmarkData != nil { score += 1 }
        if selectedSheetName != nil { score += 1 }
        if !fieldMappings.isEmpty { score += 1 }
        if outputFolderBookmarkData != nil { score += 1 }
        return score / total
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
        placeholderText
            .replacingOccurrences(of: "{{", with: "")
            .replacingOccurrences(of: "}}", with: "")
            .replacingOccurrences(of: "<<", with: "")
            .replacingOccurrences(of: ">>", with: "")
            .replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
            .replacingOccurrences(of: "${", with: "")
            .replacingOccurrences(of: "}", with: "")
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

    var systemImageName: String {
        switch self {
        case .draft: return "pencil"
        case .configured: return "checkmark.seal"
        case .running: return "hourglass"
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
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
            return value.capitalized
        case .trim:
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .dateFormat:
            guard let formatString, let date = DateParser.parse(value) else { return value }
            let formatter = DateFormatter()
            formatter.dateFormat = formatString
            return formatter.string(from: date)
        case .numberFormat:
            guard let formatString, let number = Double(value) else { return value }
            let formatter = NumberFormatter()
            formatter.positiveFormat = formatString
            return formatter.string(from: NSNumber(value: number)) ?? value
        case .currencyFormat:
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            if let formatString {
                formatter.currencyCode = formatString
            }
            if let number = Double(value) {
                return formatter.string(from: NSNumber(value: number)) ?? value
            }
            return value
        }
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
        }
    }
}

struct SheetData: Equatable {
    let headers: [String]
    let rows: [[String]]
}

struct MergeResult {
    let outputURL: URL?
    let recordCount: Int
    let duration: TimeInterval
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

    var systemImageName: String {
        switch self {
        case .template: return "doc.richtext"
        case .dataSource: return "tablecells"
        case .fieldMapping: return "arrow.left.arrow.right"
        case .output: return "folder"
        case .preview: return "doc.richtext"
        }
    }
}

enum DateParser {
    static func parse(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let timestamp = TimeInterval(trimmed) {
            return Date(timeIntervalSince1970: timestamp)
        }
        let formats = ["yyyy-MM-dd", "MM/dd/yyyy", "MMM d, yyyy"]
        let formatter = DateFormatter()
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }
}

enum FileNameSanitizer {
    static func sanitize(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let components = value.components(separatedBy: invalidCharacters)
        return components.joined(separator: "_")
    }
}
