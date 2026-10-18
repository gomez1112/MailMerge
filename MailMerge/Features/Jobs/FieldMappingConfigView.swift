import SwiftUI

struct FieldMappingConfigView: View {
    @Bindable var job: MailMergeJob
    @State private var isAutoMatching = false

    private var mappedCount: Int {
        job.mappedFieldCount
    }

    /// Fields in a stable order. SwiftData doesn't keep the order of a relationship.
    private var sortedMappings: [FieldMapping] {
        job.fieldMappings.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
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
                        .font(.callout)
                        .disabled(job.availableColumns.isEmpty || isAutoMatching)
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
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else {
                        if job.availableColumns.isEmpty {
                            Label("Choose a sheet in Data Source to load its columns.", systemImage: "tablecells")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        mappingTableHeader
                        Divider()
                        let mappings = sortedMappings
                        ForEach(mappings) { mapping in
                            MappingRow(mapping: mapping, availableColumns: job.availableColumns)
                            if mapping.id != mappings.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mappingTableHeader: some View {
        HStack(spacing: 0) {
            Text("Placeholder")
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
                .frame(width: 28)
            Text("Column")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Transform")
                .frame(width: 160, alignment: .leading)
            Text("Status")
                .frame(width: 70, alignment: .center)
        }
        .font(.caption2)
        .bold()
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
    }

    // MARK: - Auto-match

    private func autoMatch() {
        isAutoMatching = true
        let unmapped = job.fieldMappings.filter { $0.columnName == nil }
        let matches = FieldAutoMatcher.matches(
            fields: unmapped.map(\.displayName),
            columns: job.availableColumns,
            columnsInUse: Set(job.fieldMappings.compactMap(\.columnName))
        )
        for mapping in unmapped {
            guard let match = matches[mapping.displayName] else { continue }
            mapping.columnName = match.column
            mapping.isAutoMatched = true
            mapping.matchConfidence = match.confidence
        }
        isAutoMatching = false
    }
}

// MARK: - Mapping Row

private struct MappingRow: View {
    @Bindable var mapping: FieldMapping
    let availableColumns: [String]

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            fieldRow
            if mapping.transformation.usesFormatString {
                formatRow
            }
        }
        .padding(.vertical, 8)
    }

    private var fieldRow: some View {
        let columns = resolvedColumns
        return HStack(spacing: 0) {
            Text(mapping.displayName)
                .font(.callout)
                .bold()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(mapping.isMapped ? Color.mergeformBlue : Color.secondary.opacity(0.3))
                .frame(width: 28)

            Picker("Column", selection: columnSelection) {
                Text("Unmapped").tag(String?.none)
                ForEach(columns, id: \.self) { column in
                    Text(column).tag(Optional(column))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Transform", selection: transformationSelection) {
                ForEach(FieldTransformation.allCases) { transform in
                    Text(transform.label).tag(transform)
                }
            }
            .labelsHidden()
            .frame(width: 160, alignment: .leading)

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
    }

    private var formatRow: some View {
        HStack(spacing: 8) {
            Text("Format")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Format", text: formatText, prompt: Text(mapping.transformation.formatPrompt))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
                .frame(maxWidth: 220)
            Text("e.g. \(formatExample)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 120, alignment: .leading)
        }
        .padding(.trailing, 70)
    }

    /// Choosing a column by hand clears the auto-match marker.
    private var columnSelection: Binding<String?> {
        Binding {
            mapping.columnName
        } set: { newValue in
            mapping.columnName = newValue
            mapping.isAutoMatched = false
            mapping.matchConfidence = 0
        }
    }

    /// Choosing a formatting transformation starts it with a sensible format.
    private var transformationSelection: Binding<FieldTransformation> {
        Binding {
            mapping.transformation
        } set: { newValue in
            guard newValue != mapping.transformation else { return }
            mapping.transformation = newValue
            mapping.formatString = newValue.defaultFormatString()
        }
    }

    private var formatText: Binding<String> {
        Binding {
            mapping.formatString ?? ""
        } set: { newValue in
            mapping.formatString = newValue.isEmpty ? nil : newValue
        }
    }

    /// What a sample value looks like with the current format.
    private var formatExample: String {
        let sample = mapping.transformation == .dateFormat ? "2024-01-15" : "1234.5"
        return mapping.transformation.apply(to: sample, formatString: mapping.formatString)
    }

    private var resolvedColumns: [String] {
        guard let selected = mapping.columnName, !availableColumns.contains(selected) else {
            return availableColumns
        }
        return availableColumns + [selected]
    }
}
