import SwiftUI

struct FieldMappingConfigView: View {
    @Bindable var job: MailMergeJob
    @State private var isAutoMatching = false

    private var mappedCount: Int {
        job.fieldMappings.filter { $0.isMapped }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(
                title: "Field Mapping",
                subtitle: "Match template placeholders to spreadsheet columns.",
                systemImageName: "arrow.left.arrow.right"
            )

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Mapping progress")
                            .font(.headline)
                        Spacer()
                        Button {
                            autoMatch()
                        } label: {
                            Label("Auto-Match", systemImage: "sparkles")
                        }
                        .disabled(job.availableSheets.isEmpty || isAutoMatching)
                    }
                    MappingProgressView(mappedCount: mappedCount, totalCount: job.fieldMappings.count)
                }
                .padding(16)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if job.fieldMappings.isEmpty {
                        Text("No placeholders detected yet. Scan the template to start mapping.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 12) {
                            Text("Placeholder")
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("")
                                .frame(width: 24)
                            Text("Column")
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Transform")
                                .font(.caption)
                                .frame(width: 140, alignment: .leading)
                            Text("Status")
                                .font(.caption)
                                .frame(width: 80, alignment: .leading)
                        }
                        ForEach(job.fieldMappings) { mapping in
                            MappingRow(mapping: mapping, availableColumns: job.availableColumns)
                        }
                    }
                }
                .padding(16)
            }
            Spacer()
        }
    }

    private func autoMatch() {
        isAutoMatching = true
        let columnCandidates = job.availableColumns
        for mapping in job.fieldMappings {
            if mapping.columnName != nil { continue }
            let target = normalized(mapping.displayName)
            let scored = columnCandidates.map { column in
                (column, similarity(normalized(column), target))
            }
            if let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 0.6 {
                mapping.columnName = best.0
                mapping.isAutoMatched = true
                mapping.matchConfidence = best.1
            }
        }
        isAutoMatching = false
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: " ", with: "")
    }

    private func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let distance = levenshteinDistance(lhs, rhs)
        let maxLength = max(lhs.count, rhs.count)
        return 1 - (Double(distance) / Double(maxLength))
    }

    private func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        var matrix = Array(repeating: Array(repeating: 0, count: rhsChars.count + 1), count: lhsChars.count + 1)

        for i in 0...lhsChars.count {
            matrix[i][0] = i
        }
        for j in 0...rhsChars.count {
            matrix[0][j] = j
        }

        for i in 1...lhsChars.count {
            for j in 1...rhsChars.count {
                if lhsChars[i - 1] == rhsChars[j - 1] {
                    matrix[i][j] = matrix[i - 1][j - 1]
                } else {
                    let deletion = matrix[i - 1][j] + 1
                    let insertion = matrix[i][j - 1] + 1
                    let substitution = matrix[i - 1][j - 1] + 1
                    matrix[i][j] = min(deletion, insertion, substitution)
                }
            }
        }
        return matrix[lhsChars.count][rhsChars.count]
    }
}

private struct MappingRow: View {
    @Bindable var mapping: FieldMapping
    let availableColumns: [String]

    var body: some View {
        HStack(spacing: 12) {
            Text(mapping.placeholderText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            Picker("Column", selection: $mapping.columnName) {
                Text("Unmapped").tag(String?.none)
                ForEach(availableColumns, id: \.self) { column in
                    Text(column).tag(Optional(column))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Transform", selection: $mapping.transformation) {
                ForEach(FieldTransformation.allCases) { transform in
                    Text(transform.label).tag(transform)
                }
            }
            .frame(width: 140, alignment: .leading)

            HStack(spacing: 6) {
                Image(systemName: mapping.isMapped ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(mapping.isMapped ? .green : .secondary)
                if mapping.isAutoMatched {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.yellow)
                }
            }
            .frame(width: 80, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}
