import Foundation

/// Suggests spreadsheet columns for template fields by comparing their names.
nonisolated enum FieldAutoMatcher {
    nonisolated struct Match: Equatable {
        var column: String
        var confidence: Double
    }

    /// The lowest score a suggestion needs. Lower values match short look-alikes such as
    /// "Date" and "State".
    static let minimumConfidence = 0.75

    /// Suggested columns for `fields`, keyed by field name. Each column is suggested for
    /// at most one field, best matches first, and `columnsInUse` (columns already mapped
    /// by hand) aren't suggested.
    static func matches(fields: [String], columns: [String], columnsInUse: Set<String> = []) -> [String: Match] {
        var candidates: [(field: String, column: String, score: Double)] = []
        for field in fields {
            for column in columns where !columnsInUse.contains(column) {
                let score = score(field: field, column: column)
                if score >= minimumConfidence {
                    candidates.append((field, column, score))
                }
            }
        }
        candidates.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.field != rhs.field { return lhs.field < rhs.field }
            return lhs.column < rhs.column
        }

        var result: [String: Match] = [:]
        var usedColumns = columnsInUse
        for candidate in candidates where result[candidate.field] == nil && !usedColumns.contains(candidate.column) {
            result[candidate.field] = Match(column: candidate.column, confidence: candidate.score)
            usedColumns.insert(candidate.column)
        }
        return result
    }

    /// How well a column name fits a field name, from 0 to 1.
    static func score(field: String, column: String) -> Double {
        if field.caseInsensitiveCompare(column) == .orderedSame { return 1 }
        let lhs = normalized(field)
        let rhs = normalized(column)
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        // "First_Name" and "First Name" are the same name written differently.
        if lhs == rhs { return 0.99 }
        // "Zip" fits "Zip Code" and "Name" fits "Full Name".
        let (shorter, longer) = lhs.count <= rhs.count ? (lhs, rhs) : (rhs, lhs)
        if shorter.count >= 3, longer.hasPrefix(shorter) || longer.hasSuffix(shorter) {
            return 0.8
        }
        return similarity(lhs, rhs)
    }

    private static func normalized(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let distance = levenshteinDistance(lhs, rhs)
        let maxLength = max(lhs.count, rhs.count)
        return 1 - (Double(distance) / Double(maxLength))
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        var matrix = Array(repeating: Array(repeating: 0, count: rhsChars.count + 1), count: lhsChars.count + 1)
        for i in 0...lhsChars.count { matrix[i][0] = i }
        for j in 0...rhsChars.count { matrix[0][j] = j }
        for i in 1...lhsChars.count {
            for j in 1...rhsChars.count {
                if lhsChars[i - 1] == rhsChars[j - 1] {
                    matrix[i][j] = matrix[i - 1][j - 1]
                } else {
                    matrix[i][j] = min(matrix[i - 1][j], matrix[i][j - 1], matrix[i - 1][j - 1]) + 1
                }
            }
        }
        return matrix[lhsChars.count][rhsChars.count]
    }
}
