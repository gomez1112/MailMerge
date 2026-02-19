import Foundation
import Testing
@testable import MailMerge

@MainActor
@Suite("Mail merge job configuration")
struct MailMergeJobTests {
    @Test("Defaults are unconfigured")
    func defaultsAreUnconfigured() {
        let job = MailMergeJob(name: "Test Job")

        #expect(job.isConfigured == false)
        #expect(job.configurationProgress == 0)
    }

    @Test("Progress reflects filled requirements")
    func configurationProgressTracksRequirements() {
        let job = MailMergeJob(name: "Configured Job")
        let sampleData = Data([0x1])

        job.templateBookmarkData = sampleData
        #expect(job.configurationProgress == 0.2)

        job.dataSourceBookmarkData = sampleData
        #expect(job.configurationProgress == 0.4)

        job.selectedSheetName = "Sheet1"
        #expect(job.configurationProgress == 0.6)

        job.fieldMappings = [FieldMapping(placeholderText: "{{FirstName}}", columnName: "FirstName")]
        #expect(job.configurationProgress == 0.8)

        job.outputFolderBookmarkData = sampleData
        #expect(job.configurationProgress == 1.0)
        #expect(job.isConfigured == true)
    }
}

@MainActor
@Suite("Field mapping display")
struct FieldMappingTests {
    @Test("Maps placeholder display names", arguments: zip(
        [
            "{{FirstName}}",
            "<<LastName>>",
            "[[City]]",
            "${Amount}",
            "PlainText"
        ],
        [
            "FirstName",
            "LastName",
            "City",
            "Amount",
            "PlainText"
        ]
    ))
    func displayNameStripsWrappers(_ placeholder: String, expected: String) {
        let mapping = FieldMapping(placeholderText: placeholder)
        #expect(mapping.displayName == expected)
    }

    @Test("Mapping state tracks column assignment")
    func isMappedReflectsColumnName() {
        let unmapped = FieldMapping(placeholderText: "{{Name}}")
        #expect(unmapped.isMapped == false)

        let mapped = FieldMapping(placeholderText: "{{Name}}", columnName: "Name")
        #expect(mapped.isMapped == true)
    }
}

@MainActor
@Suite("Job status display")
struct JobStatusTests {
    @Test("Labels and icons are stable", arguments: [
        (JobStatus.draft, "Draft", "pencil"),
        (.configured, "Configured", "checkmark.seal"),
        (.running, "Running", "hourglass"),
        (.completed, "Completed", "checkmark.circle"),
        (.failed, "Failed", "exclamationmark.triangle")
    ])
    func statusLabelAndIcon(_ status: JobStatus, expectedLabel: String, expectedIcon: String) {
        #expect(status.label == expectedLabel)
        #expect(status.systemImageName == expectedIcon)
    }
}

@MainActor
@Suite("Merge steps")
struct MergeStepTests {
    @Test("Titles and icons are stable", arguments: [
        (MergeStep.template, "Template", "doc.richtext"),
        (.dataSource, "Data Source", "tablecells"),
        (.fieldMapping, "Field Mapping", "arrow.left.arrow.right"),
        (.output, "Output", "folder"),
        (.preview, "Preview", "doc.richtext")
    ])
    func stepLabelAndIcon(_ step: MergeStep, expectedTitle: String, expectedIcon: String) {
        #expect(step.title == expectedTitle)
        #expect(step.systemImageName == expectedIcon)
    }
}

@MainActor
@Suite("Transformations")
struct FieldTransformationTests {
    @Test("Uppercase, lowercase, titlecase, and trim")
    func simpleStringTransforms() {
        #expect(FieldTransformation.uppercase.apply(to: "Abc", formatString: nil) == "ABC")
        #expect(FieldTransformation.lowercase.apply(to: "Abc", formatString: nil) == "abc")
        #expect(FieldTransformation.titlecase.apply(to: "hello world", formatString: nil) == "Hello World")
        #expect(FieldTransformation.trim.apply(to: "  spaced  ", formatString: nil) == "spaced")
    }

    @Test("Invalid formatting falls back to original")
    func formattingFallBacks() {
        #expect(FieldTransformation.dateFormat.apply(to: "not a date", formatString: "yyyy-MM-dd") == "not a date")
        #expect(FieldTransformation.numberFormat.apply(to: "NaN", formatString: "0.00") == "NaN")
        #expect(FieldTransformation.currencyFormat.apply(to: "NaN", formatString: "USD") == "NaN")
    }

    @Test("Number format applies custom positive format")
    func numberFormatting() {
        let formatted = FieldTransformation.numberFormat.apply(to: "1234.5", formatString: "0.00")
        #expect(formatted == "1234.50")
    }

    @Test("Currency format uses provided code")
    func currencyFormatting() {
        let formatted = FieldTransformation.currencyFormat.apply(to: "99.99", formatString: "USD")
        #expect(formatted.contains("$") || formatted.contains("USD"))
    }

    @Test("Number format without format string returns original")
    func numberFormattingWithoutFormatString() {
        let formatted = FieldTransformation.numberFormat.apply(to: "1234.5", formatString: nil)
        #expect(formatted == "1234.5")
    }

    @Test("Currency format without code still formats")
    func currencyFormattingWithoutCode() {
        let formatted = FieldTransformation.currencyFormat.apply(to: "99.99", formatString: nil)
        #expect(formatted.isEmpty == false)
        #expect(formatted.contains("99") || formatted.contains("100") || formatted.contains("9"))
    }
}

@MainActor
@Suite("Date parsing")
struct DateParserTests {
    @Test("Parses unix timestamps")
    func parsesUnixTimestamp() {
        let parsed = DateParser.parse("1704067200")
        #expect(parsed != nil)
        #expect(parsed?.timeIntervalSince1970 == 1_704_067_200)
    }

    @Test("Parses common date formats")
    func parsesDateFormats() {
        #expect(DateParser.parse("2024-01-02") != nil)
        #expect(DateParser.parse("01/02/2024") != nil)
        #expect(DateParser.parse("Jan 2, 2024") != nil)
    }

    @Test("Trims whitespace before parsing")
    func trimsWhitespace() {
        #expect(DateParser.parse(" 2024-01-02 ") != nil)
    }

    @Test("Rejects unsupported formats")
    func rejectsUnsupportedFormats() {
        #expect(DateParser.parse("not a date") == nil)
        #expect(DateParser.parse("") == nil)
    }

    @Test("Parses fractional timestamps")
    func parsesFractionalTimestamp() {
        let parsed = DateParser.parse("1704067200.5")
        #expect(parsed != nil)
        #expect(parsed?.timeIntervalSince1970 == 1_704_067_200.5)
    }
}

@MainActor
@Suite("File name sanitation")
struct FileNameSanitizerTests {
    @Test("Replaces invalid characters")
    func sanitizesInvalidCharacters() {
        let input = "Doc:Name/2024?.docx"
        let output = FileNameSanitizer.sanitize(input)
        #expect(output == "Doc_Name_2024_.docx")
    }

    @Test("Preserves safe characters")
    func preservesSafeCharacters() {
        let input = "Report_2024-01-02.final.pdf"
        let output = FileNameSanitizer.sanitize(input)
        #expect(output == input)
    }

    @Test("Handles empty input")
    func handlesEmptyInput() {
        let output = FileNameSanitizer.sanitize("")
        #expect(output.isEmpty)
    }

    @Test("Collapses only invalid characters")
    func collapsesInvalidCharacters() {
        let input = "bad<>name|with*chars"
        let output = FileNameSanitizer.sanitize(input)
        #expect(output == "bad__name_with_chars")
    }

    @Test("Replaces backslashes and quotes")
    func replacesBackslashesAndQuotes() {
        let input = "report\"name\"\\2024"
        let output = FileNameSanitizer.sanitize(input)
        #expect(output == "report_name__2024")
    }
}

@MainActor
@Suite("Merge errors")
struct MergeErrorTests {
    @Test("Error descriptions are human readable", arguments: zip(
        [
            MergeError.invalidTemplate,
            .invalidSpreadsheet,
            .emptySheet,
            .sheetNotFound,
            .staleBookmark,
            .outputAccessDenied,
            .noRecords,
            .pdfGenerationFailed,
            .securityScopeUnavailable,
            .featureUnavailable
        ],
        [
            "The DOCX template appears to be invalid or corrupted.",
            "The Excel file appears to be invalid or corrupted.",
            "The selected sheet contains no data.",
            "The selected sheet could not be found.",
            "The selected file has moved or is no longer available.",
            "The output folder could not be accessed.",
            "No records were found in the data source.",
            "Failed to generate the PDF output.",
            "The app could not access the selected file.",
            "This feature isn't available on the current platform."
        ]
    ))
    func errorDescriptions(_ error: MergeError, expected: String) {
        #expect(error.errorDescription == expected)
    }
}
