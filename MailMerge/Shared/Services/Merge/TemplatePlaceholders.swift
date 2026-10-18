import Foundation

/// The placeholder syntaxes templates can use: `{{Name}}`, `<<Name>>`, `${Name}`, and
/// `[[Name]]`.
///
/// A placeholder never spans a line break, and its name is compared with surrounding
/// whitespace trimmed, so `{{ Name }}` and `{{Name}}` are the same field. Scanning and
/// merging share this definition so they always agree on what a placeholder is.
nonisolated enum TemplatePlaceholders {
    struct Occurrence: Equatable {
        /// The placeholder's range, including its delimiters, in UTF-16 units.
        var range: NSRange
        var name: String
    }

    /// Every placeholder in `text`, in order.
    static func occurrences(in text: String) -> [Occurrence] {
        // `\v` excludes every kind of line break, including Word's soft line breaks.
        // The name can't contain the delimiter characters, so in "${{Amount}}" the
        // dollar sign stays text and "{{Amount}}" is the placeholder.
        let syntax = /\{\{([^{}\v]+?)\}\}|<<([^<>\v]+?)>>|\$\{([^{}\v]+?)\}|\[\[([^\[\]\v]+?)\]\]/
        return text.matches(of: syntax).compactMap { match in
            guard let rawName = match.output.1 ?? match.output.2 ?? match.output.3 ?? match.output.4 else {
                return nil
            }
            let name = rawName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return Occurrence(range: NSRange(match.range, in: text), name: name)
        }
    }

    /// The distinct field names used in `text`, sorted.
    static func fieldNames(in text: String) -> [String] {
        Set(occurrences(in: text).map(\.name)).sorted()
    }

    /// The field a stored placeholder refers to. Older versions could store a placeholder
    /// with its delimiters, such as "{{Name}}".
    static func fieldName(for placeholderText: String) -> String {
        let trimmed = placeholderText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullRange = NSRange(trimmed.startIndex..., in: trimmed)
        if let occurrence = occurrences(in: trimmed).first, occurrence.range == fullRange {
            return occurrence.name
        }
        return trimmed
    }
}
