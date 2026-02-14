import Foundation
import Testing
@testable import MailMerge

// MARK: - DateParser

struct DateParserTests {
    @Test(arguments: [
        "2024-01-15",
        "12/31/2024",
        "Jan 2, 2025"
    ])
    func dateParserHandlesSupportedFormats(_ input: String) {
        let date = DateParser.parse(input)
        #expect(date != nil)
    }

    @Test(arguments: [
        "",
        "not a date",
        "2024/13/40"
    ])
    func dateParserRejectsUnsupportedFormats(_ input: String) {
        let date = DateParser.parse(input)
        #expect(date == nil)
    }

    @Test
    func dateParserHandlesUnixTimestamp() {
        let date = DateParser.parse("0")
        #expect(date?.timeIntervalSince1970 == 0)
    }
}

// MARK: - FileNameSanitizer

struct FileNameSanitizerTests {
    @Test(arguments: [
        ("Report:{Row}/Name", "Report__Row__Name"),
        ("A<B>C", "A_B_C"),
        ("Invoice: 01/02/2025", "Invoice_ 01_02_2025")
    ])
    func fileNameSanitizerReplacesInvalidCharacters(_ input: String, _ expected: String) {
        let sanitized = FileNameSanitizer.sanitize(input)
        #expect(sanitized == expected)
    }

    @Test(arguments: [
        "Simple_Name",
        "Quarterly Report 2025",
        "Budget-Plan"
    ])
    func fileNameSanitizerPreservesValidCharacters(_ input: String) {
        let sanitized = FileNameSanitizer.sanitize(input)
        #expect(sanitized == input)
    }
}

// MARK: - FieldTransformation

struct FieldTransformationTests {
    @Test(arguments: [
        (FieldTransformation.none, "Keep", "Keep"),
        (FieldTransformation.uppercase, "abc", "ABC"),
        (FieldTransformation.lowercase, "ABC", "abc"),
        (FieldTransformation.titlecase, "hello world", "Hello World"),
        (FieldTransformation.trim, "  x  ", "x")
    ])
    func fieldTransformationBasicCases(_ transform: FieldTransformation, _ input: String, _ expected: String) {
        let output = transform.apply(to: input, formatString: nil)
        #expect(output == expected)
    }

    @Test(arguments: [
        ("2024-01-15", "yyyy/MM/dd", "2024/01/15"),
        ("12/31/2024", "yyyy-MM-dd", "2024-12-31")
    ])
    func fieldTransformationDateFormat(_ input: String, _ format: String, _ expected: String) {
        let output = FieldTransformation.dateFormat.apply(to: input, formatString: format)
        #expect(output == expected)
    }

    @Test(arguments: [
        ("3.5", "0.00", "3.50"),
        ("1000", "#,##0", "1,000")
    ])
    func fieldTransformationNumberFormat(_ input: String, _ format: String, _ expected: String) {
        let output = FieldTransformation.numberFormat.apply(to: input, formatString: format)
        #expect(output == expected)
    }
}
// MARK: - JobStatus

struct JobStatusTests {
    @Test(arguments: [
        (JobStatus.draft, "Draft", "pencil"),
        (JobStatus.configured, "Configured", "checkmark.seal"),
        (JobStatus.running, "Running", "hourglass"),
        (JobStatus.completed, "Completed", "checkmark.circle"),
        (JobStatus.failed, "Failed", "exclamationmark.triangle")
    ])
    func jobStatusLabelsAndIcons(_ status: JobStatus, _ label: String, _ icon: String) {
        #expect(status.label == label)
        #expect(status.systemImageName == icon)
    }
}

