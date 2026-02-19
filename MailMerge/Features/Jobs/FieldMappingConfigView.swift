import SwiftUI

struct FieldMappingConfigView: View {
    @Environment(\.services) private var services
    @Bindable var job: MailMergeJob
    @State private var isAutoMatching = false
    @State private var isLoadingColumns = false

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

            // Progress card
            ConfigCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        CardLabel(title: "Mapping Progress", systemImage: "chart.bar.fill")
                        Spacer()
                        Button {
                            autoMatch()
                        } label: {
                            if isAutoMatching {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.mini)
                                    Text("Matching…")
                                }
                            } else {
                                Label("Auto-Match", systemImage: "sparkles")
                            }
                        }
                        .font(.system(size: 12))
                        .disabled(job.availableColumns.isEmpty || isAutoMatching || isLoadingColumns)
                    }
                    MappingProgressView(mappedCount: mappedCount, totalCount: job.fieldMappings.count)
                }
            }

            // Mappings table card
            ConfigCard {
                VStack(alignment: .leading, spacing: 12) {
                    CardLabel(title: "Field Assignments", systemImage: "arrow.left.arrow.right")

                    if job.fieldMappings.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "wand.and.stars")
                                .foregroundStyle(.tertiary)
                            Text("No placeholders detected yet. Scan the template in Step 1 to start mapping.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else {
                        mappingTableHeader
                        Divider()
                        ForEach(job.fieldMappings) { mapping in
                            MappingRow(mapping: mapping, availableColumns: job.availableColumns)
                            if mapping.id != job.fieldMappings.last?.id {
                                Divider()
                                    .padding(.leading, 32)
                            }
                        }
                        .onMove { from, to in
                            job.fieldMappings.move(fromOffsets: from, toOffset: to)
                        }
                    }
                }
            }

            Spacer()
        }
        .task(id: job.selectedSheetName) {
            await loadColumnsIfNeeded()
        }
    }

    private var mappingTableHeader: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: 28)
            Text("Placeholder")
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
                .frame(width: 28)
            Text("Column")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Transform")
                .frame(width: 130, alignment: .leading)
            Text("Status")
                .frame(width: 70, alignment: .center)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .tracking(0.3)
    }

    // MARK: - Auto-match

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

    @MainActor
    private func applyAvailableColumns(_ headers: [String]) {
        let cleanedHeaders = headers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen: Set<String> = []
        let uniqueHeaders = cleanedHeaders.filter { seen.insert($0).inserted }
        job.availableColumns = uniqueHeaders
    }

    private func loadColumnsIfNeeded() async {
        guard job.availableColumns.isEmpty,
              let bookmarkData = job.dataSourceBookmarkData,
              let sheetName = job.selectedSheetName else {
            return
        }
        isLoadingColumns = true
        do {
            let headers = try await services.mergeEngine.getColumnHeaders(
                bookmarkData: bookmarkData,
                sheetName: sheetName
            )
            await MainActor.run {
                applyAvailableColumns(headers)
                isLoadingColumns = false
            }
        } catch {
            await MainActor.run {
                isLoadingColumns = false
            }
        }
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

// MARK: - Mapping Row

private struct MappingRow: View {
    @Bindable var mapping: FieldMapping
    let availableColumns: [String]

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
                .frame(width: 28)

            Text(mapping.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(mapping.isMapped ? Color.mergeformBlue : Color.secondary.opacity(0.3))
                .frame(width: 28)

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
            .frame(width: 130, alignment: .leading)

            // Status indicator
            HStack(spacing: 4) {
                if mapping.isMapped {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if mapping.isAutoMatched {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.quaternary)
                }
            }
            .font(.system(size: 13))
            .frame(width: 70, alignment: .center)
        }
        .padding(.vertical, 8)
    }
}
