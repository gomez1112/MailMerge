import Foundation

/// A template shown in the Templates tab, combining every job that uses the same file.
struct TemplateLibraryItem: Identifiable {
    var id: String
    var fileName: String
    var lastUsed: Date
    var usageCount: Int
    var bookmarkData: Data

    /// One job's template.
    struct Source {
        var bookmarkData: Data
        var fileName: String
        var lastUsed: Date
    }

    /// Groups jobs' templates into library items, most recently used first.
    /// `fileIdentity` returns a stable identifier for the file a bookmark points to.
    ///
    /// Every bookmark is unique even for the same file, so sources are grouped by the
    /// file they point to; a bookmark that can't be resolved is its own item.
    static func items(from sources: [Source], fileIdentity: (Data) -> String?) -> [TemplateLibraryItem] {
        let grouped = Dictionary(grouping: sources) { source in
            fileIdentity(source.bookmarkData) ?? source.bookmarkData.base64EncodedString()
        }
        return grouped.compactMap { key, values in
            guard let latest = values.max(by: { $0.lastUsed < $1.lastUsed }) else { return nil }
            return TemplateLibraryItem(
                id: key,
                fileName: latest.fileName,
                lastUsed: latest.lastUsed,
                usageCount: values.count,
                bookmarkData: latest.bookmarkData
            )
        }
        .sorted(by: { $0.lastUsed > $1.lastUsed })
    }
}
