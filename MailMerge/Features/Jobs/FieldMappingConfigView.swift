import SwiftUI

struct FieldMappingConfigView: View {
    @Bindable var job: MailMergeJob
    /// Counts Auto-Match runs so its symbol can bounce each time.
    @State private var autoMatchRuns = 0

    private var mappedCount: Int {
        job.mappedFieldCount
    }

    /// Fields in a stable order. SwiftData doesn't keep the order of a relationship.
    private var sortedMappings: [FieldMapping] {
        job.fieldMappings.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.section) {
            SectionHeader(
                title: "Field Mapping",
                subtitle: "Match each placeholder in the template to a spreadsheet column.",
                systemImageName: "arrow.left.arrow.right",
                iconColor: .purple
            )

            ConfigCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        CardLabel(title: "Progress", systemImage: "chart.bar.fill")
                        Spacer()
                        Button(action: autoMatch) {
                            Label("Auto-Match", systemImage: "sparkles")
                                .symbolEffect(.bounce, value: autoMatchRuns)
                        }
                        .disabled(job.availableColumns.isEmpty)
                        .help("Match unmapped fields to columns with similar names")
                    }
                    MappingProgressView(mappedCount: mappedCount, totalCount: job.fieldMappings.count)
                }
            }
            .revealOnAppear(order: 0)

            ConfigCard {
                VStack(alignment: .leading, spacing: Metrics.compact) {
                    CardLabel(title: "Fields", systemImage: "arrow.left.arrow.right")

                    if job.fieldMappings.isEmpty {
                        Label("No fields yet. Choose and scan a template in the Template step.", systemImage: "wand.and.sparkles")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
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
            .revealOnAppear(order: 1)
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
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .tracking(0.5)
        .padding(.horizontal, 8)
    }

    // MARK: - Auto-match

    private func autoMatch() {
        autoMatchRuns += 1
        job.autoMatchUnmappedFields()
    }
}

// MARK: - Mapping Row

private struct MappingRow: View {
    @Bindable var mapping: FieldMapping
    let availableColumns: [String]

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            fieldRow
            if mapping.transformation.usesFormatString {
                formatRow
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(
            isHovering ? Color.primary.opacity(0.035) : .clear,
            in: .rect(cornerRadius: Metrics.tileRadius)
        )
        .onHover { isHovering = $0 }
        .motion(Motion.quick, value: isHovering)
        .motion(Motion.standard, value: mapping.transformation)
        .motion(Motion.lively, value: mapping.isMapped)
        .motion(Motion.lively, value: mapping.isAutoMatched)
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

            HStack(spacing: 4) {
                Image(systemName: mapping.isMapped ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(mapping.isMapped ? AnyShapeStyle(.green) : AnyShapeStyle(.quaternary))
                    .contentTransition(.symbolEffect(.replace))
                if mapping.isAutoMatched {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.mergeformOrange)
                        .transition(.scale.combined(with: .opacity))
                        .help("Matched automatically")
                }
            }
            .font(.system(size: 15))
            .frame(width: 70, alignment: .center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(mapping.isMapped ? (mapping.isAutoMatched ? "Mapped automatically" : "Mapped") : "Not mapped")
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
